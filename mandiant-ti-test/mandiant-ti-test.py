#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import json
import mmguero
import logging
import os
import sys
import mandiant_threatintel

from collections import defaultdict
from dateparser import parse as ParseDate
from datetime import datetime
from pytz import utc as UTCTimeZone
from types import GeneratorType, FunctionType, LambdaType

script_name = os.path.basename(__file__)
script_path = os.path.dirname(os.path.realpath(__file__))

skip_attr_map = defaultdict(lambda: False)


def mandiant_json_serializer(obj):
    """
    JSON serializer for mandiant_threatintel.APIResponse object (for debug output)
    """
    if isinstance(obj, datetime):
        return obj.astimezone(UTCTimeZone).isoformat()

    elif isinstance(obj, GeneratorType):
        return [mandiant_json_serializer(item) for item in obj]

    elif isinstance(obj, list):
        return [mandiant_json_serializer(item) for item in obj]

    elif isinstance(obj, dict):
        return {key: mandiant_json_serializer(value) for key, value in obj.items()}

    elif isinstance(obj, set):
        return {mandiant_json_serializer(item) for item in obj}

    elif isinstance(obj, tuple):
        return tuple(mandiant_json_serializer(item) for item in obj)

    elif isinstance(obj, FunctionType):
        return f"function {obj.__name__}" if obj.__name__ != "<lambda>" else "lambda"

    elif isinstance(obj, LambdaType):
        return "lambda"

    elif (not hasattr(obj, "__str__") or obj.__str__ is object.__str__) and (
        not hasattr(obj, "__repr__") or obj.__repr__ is object.__repr__
    ):
        return obj.__class__.__name__

    else:
        return str(obj)


def mandiant_object_as_json_str(indicator, api_response_only=True):
    global skip_attr_map

    return json.dumps(
        (
            indicator._api_response
            if api_response_only
            else {
                key: getattr(indicator, key)
                for key in indicator.__dir__()
                if (skip_attr_map[key] == False)
                and (not key.startswith("_"))
                and (not callable(getattr(indicator, key)))
            }
        ),
        default=mandiant_json_serializer,
    )


###################################################################################################
def main():
    global skip_attr_map

    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawTextHelpFormatter,
        add_help=True,
    )
    parser.add_argument(
        '--verbose',
        '-v',
        action='count',
        default=1,
        help='Increase verbosity (e.g., -v, -vv, etc.)',
    )
    parser.add_argument(
        '--start',
        dest='start',
        type=str,
        default=None,
        help="Retrieve indicators beginning at this timestamp",
    )
    parser.add_argument(
        '--end',
        dest='end',
        type=str,
        default=None,
        help="Retrieve indicators ending at this timestamp",
    )
    parser.add_argument(
        '-s',
        '--score',
        dest='score',
        type=int,
        default=0,
        help="Minimum 'mscore' or 'confidence'",
    )
    parser.add_argument(
        '-p',
        '--page-size',
        dest='pageSize',
        type=int,
        default=1000,
        help="Page size for API requests",
    )
    parser.add_argument(
        '-x',
        '--exclude-osint',
        dest='excludeOsInt',
        type=mmguero.str2bool,
        nargs='?',
        const=True,
        default=False,
        help='Exclude Open Source Intelligence from results',
    )
    parser.add_argument(
        '-c',
        '--include-campaigns',
        dest='includeCampaigns',
        type=mmguero.str2bool,
        nargs='?',
        const=True,
        default=False,
        help='Include campaigns',
    )
    parser.add_argument(
        '-r',
        '--include-reports',
        dest='includeReports',
        type=mmguero.str2bool,
        nargs='?',
        const=True,
        default=False,
        help='Include reports',
    )
    parser.add_argument(
        '-t',
        '--include-threat-rating',
        dest='includeThreatRating',
        type=mmguero.str2bool,
        nargs='?',
        const=True,
        default=False,
        help='Include threat rating',
    )
    parser.add_argument(
        '-m',
        '--include-misp',
        dest='includeMisp',
        type=mmguero.str2bool,
        nargs='?',
        const=True,
        default=True,
        help='Include MISP',
    )
    parser.add_argument(
        '-g',
        '--include-category',
        dest='includeCategory',
        type=mmguero.str2bool,
        nargs='?',
        const=True,
        default=True,
        help='Include category',
    )
    parser.add_argument(
        '--api',
        dest='apiKey',
        metavar='<string>',
        type=str,
        default=os.getenv('MANDIANT_TI_API_KEY', None),
        help="Mandiant TI API Key",
    )
    parser.add_argument(
        '--api-response-only',
        dest='apiResponseOnly',
        type=mmguero.str2bool,
        nargs='?',
        const=True,
        default=True,
        help="Print JSON from API response only (vs deserialize the object)",
    )
    parser.add_argument(
        '--secret',
        dest='secretKey',
        metavar='<string>',
        type=str,
        default=os.getenv('MANDIANT_TI_SECRET_KEY', None),
        help="Mandiant TI Secret Key",
    )
    try:
        parser.error = parser.exit
        args, extraArgs = parser.parse_known_args()
    except SystemExit as e:
        if str(e) != '0':
            mmguero.eprint(f'Invalid argument(s): {e}')
        sys.exit(2)

    # configure logging levels based on -v, -vv, -vvv, etc.
    args.verbose = logging.CRITICAL - (10 * args.verbose) if args.verbose > 0 else 0
    logging.basicConfig(
        level=args.verbose, format='%(asctime)s %(levelname)s: %(message)s', datefmt='%Y-%m-%d %H:%M:%S'
    )
    logging.info(os.path.join(script_path, script_name))
    logging.info("Arguments: {}".format(sys.argv[1:]))
    logging.info("Arguments: {}".format(args))
    if extraArgs:
        logging.info("Extra arguments: {}".format(extraArgs))
    if args.verbose > logging.DEBUG:
        sys.tracebacklimit = 0

    skip_attr_map['campaigns'] = not args.includeCampaigns
    skip_attr_map['category'] = not args.includeCategory
    skip_attr_map['misp'] = not args.includeMisp
    skip_attr_map['reports'] = not args.includeReports
    skip_attr_map['threat_rating'] = not args.includeThreatRating
    skip_attr_map['attributed_associations'] = True

    ParseDateArg = lambda valStr, defaultStr: (
        ParseDate(valStr).astimezone(UTCTimeZone) if valStr else ParseDate(defaultStr).astimezone(UTCTimeZone)
    )

    mati_client = mandiant_threatintel.ThreatIntelClient(
        api_key=args.apiKey,
        secret_key=args.secretKey,
    )

    for indicator in mati_client.Indicators.get_list(
        minimum_mscore=args.score,
        page_size=args.pageSize,
        exclude_osint=args.excludeOsInt,
        include_campaigns=args.includeCampaigns,
        include_reports=args.includeReports,
        include_threat_rating=args.includeThreatRating,
        include_misp=args.includeMisp,
        include_category=args.includeCategory,
        start_epoch=ParseDateArg(args.start, "one hour ago"),
        end_epoch=ParseDateArg(args.end, "now"),
    ):
        print(mandiant_object_as_json_str(indicator, api_response_only=args.apiResponseOnly))


if __name__ == '__main__':
    main()
