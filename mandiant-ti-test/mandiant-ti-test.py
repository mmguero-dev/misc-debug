#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import json
import logging
import os
import sys
import mandiant_threatintel

from dateparser import parse as ParseDate
from datetime import datetime
from pytz import utc as UTCTimeZone
from types import GeneratorType, FunctionType, LambdaType

script_name = os.path.basename(__file__)
script_path = os.path.dirname(os.path.realpath(__file__))


def json_serializer(obj):

    if isinstance(obj, datetime):
        return obj.astimezone(UTCTimeZone).isoformat()

    elif isinstance(obj, GeneratorType):
        return list(map(json_serializer, obj))

    elif isinstance(obj, list):
        return [json_serializer(item) for item in obj]

    elif isinstance(obj, dict):
        return {key: json_serializer(value) for key, value in obj.items()}

    elif isinstance(obj, set):
        return {json_serializer(item) for item in obj}

    elif isinstance(obj, tuple):
        return tuple(json_serializer(item) for item in obj)

    elif isinstance(obj, FunctionType):
        return f"function {obj.__name__}" if obj.__name__ != "<lambda>" else "lambda"

    elif (not hasattr(obj, "__str__") or obj.__str__ is object.__str__) and (
        not hasattr(obj, "__repr__") or obj.__repr__ is object.__repr__
    ):
        return obj.__class__.__name__

    else:
        return str(obj)


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
    '--api',
    dest='apiKey',
    metavar='<string>',
    type=str,
    default=os.getenv('MANDIANT_TI_API_KEY', None),
    help="Mandiant TI API Key",
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
logging.basicConfig(level=args.verbose, format='%(asctime)s %(levelname)s: %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
logging.info(os.path.join(script_path, script_name))
logging.info("Arguments: {}".format(sys.argv[1:]))
logging.info("Arguments: {}".format(args))
if extraArgs:
    logging.info("Extra arguments: {}".format(extraArgs))
if args.verbose > logging.DEBUG:
    sys.tracebacklimit = 0

ParseDateArg = lambda valStr, defaultStr: (
    ParseDate(valStr).astimezone(UTCTimeZone) if valStr else ParseDate(defaultStr).astimezone(UTCTimeZone)
)

start_epoch = ParseDateArg(args.start, "one hour ago")
end_epoch = ParseDateArg(args.end, "now")
logging.info(f"{start_epoch} to {end_epoch}")

mati_client = mandiant_threatintel.ThreatIntelClient(
    api_key=args.apiKey,
    secret_key=args.secretKey,
)

for indicator in mati_client.Indicators.get_list(
    start_epoch=start_epoch,
    end_epoch=end_epoch,
):
    logging.info(
        json.dumps(
            {
                key: getattr(indicator, key)
                for key in indicator.__dir__()
                if not key.startswith("__") and not callable(getattr(indicator, key))
            },
            default=json_serializer,
        )
    )