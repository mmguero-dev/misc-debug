#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import ipaddress
import json
import logging
import os
import pynetbox
import re
import sys
import time

from collections.abc import Iterable
from slugify import slugify

###################################################################################################
args = None
script_name = os.path.basename(__file__)
script_path = os.path.dirname(os.path.realpath(__file__))
orig_path = os.getcwd()

###################################################################################################
def is_ip_address(x):
    try:
        ip = ipaddress.ip_address(x)
        return True
    except Exception:
        return False


def is_ip_v4_address(x):
    try:
        ip = ipaddress.IPv4Address(x)
        return True
    except Exception:
        return False


def is_ip_v6_address(x):
    try:
        ip = ipaddress.IPv6Address(x)
        return True
    except Exception:
        return False


def is_ip_network(x):
    try:
        ip = ipaddress.ip_network(x)
        return True
    except Exception:
        return False


###################################################################################################
# main
def main():
    global args

    parser = argparse.ArgumentParser(
        description='\n'.join([]),
        formatter_class=argparse.RawTextHelpFormatter,
        add_help=False,
        usage='{} <arguments>'.format(script_name),
    )
    parser.add_argument(
        '--verbose',
        '-v',
        action='count',
        default=1,
        help='Increase verbosity (e.g., -v, -vv, etc.)',
    )
    parser.add_argument(
        '--wait',
        dest='wait',
        action='store_true',
        help='Wait for connection first',
    )
    parser.add_argument(
        '--no-wait',
        dest='wait',
        action='store_false',
        help='Do not wait for connection (error if connection fails)',
    )
    parser.set_defaults(wait=True)
    parser.add_argument(
        '-u',
        '--url',
        dest='netboxUrl',
        type=str,
        default='http://localhost:8080/netbox',
        required=False,
        help="NetBox Base URL",
    )
    parser.add_argument(
        '-t',
        '--token',
        dest='netboxToken',
        type=str,
        default=None,
        required=True,
        help="NetBox API Token",
    )
    parser.add_argument(
        '-i',
        '--ip',
        dest='ipSearchKey',
        type=str,
        default=None,
        required=False,
        help="Search by this IP address",
    )
    try:
        parser.error = parser.exit
        args = parser.parse_args()
        if args.ipSearchKey and not is_ip_address(args.ipSearchKey):
            raise ValueError(f"{args.ipSearchKey} is not a valid IP address")
    except SystemExit:
        parser.print_help()
        exit(2)
    except Exception as e:
        logging.error(e)
        parser.print_help()
        exit(2)

    args.verbose = logging.ERROR - (10 * args.verbose) if args.verbose > 0 else 0
    logging.basicConfig(
        level=args.verbose, format='%(asctime)s %(levelname)s: %(message)s', datefmt='%Y-%m-%d %H:%M:%S'
    )
    logging.debug(os.path.join(script_path, script_name))
    logging.debug("Arguments: {}".format(sys.argv[1:]))
    logging.debug("Arguments: {}".format(args))
    if args.verbose > logging.DEBUG:
        sys.tracebacklimit = 0

    # create connection to netbox API
    nb = pynetbox.api(
        args.netboxUrl,
        token=args.netboxToken,
        threading=True,
    )

    # wait for a good connection
    sitesConnTest = None
    while args.wait:
        try:
            sitesConnTest = nb.dcim.sites.all()
            break
        except Exception as e:
            logging.info(f"{type(e).__name__}: {e}")
            logging.debug("retrying in a few seconds...")
            time.sleep(5)

    # retrieve the list VRFs containing IP address prefixes containing the search key
    vrfs = list(
        set(
            [
                x.vrf
                for x in (
                    nb.ipam.prefixes.filter(
                        contains=args.ipSearchKey,
                    )
                    if args.ipSearchKey
                    else nb.ipam.prefixes.all()
                )
                if x.vrf
            ]
        )
    )

    # retrieve the list IP addresses where address matches the search key, limited to "assigned" addresses.
    # then, for those IP addresses, search for devices pertaining to the interfaces assigned to each
    # IP address (e.g., ipam.ip_address -> dcim.interface -> dcim.device, or
    # ipam.ip_address -> virtualization.interface -> virtualization.virtual_machine)
    devices = []
    for ipAddress in [
        x
        for x in (
            nb.ipam.ip_addresses.filter(
                address=args.ipSearchKey,
            )
            if args.ipSearchKey
            else nb.ipam.ip_addresses.all()
        )
        if x.assigned_object
    ]:
        ipAddressObj = ipAddress.assigned_object
        if hasattr(ipAddressObj, 'device'):
            devices.append(ipAddressObj.device)
        elif hasattr(ipAddressObj, 'virtual_machine'):
            devices.append(ipAddressObj.virtual_machine)

    # -------------------------------
    print(
        json.dumps(
            {
                "vrfs": [v.serialize() for v in vrfs],
                "devices": [d.serialize() for d in devices],
            },
            indent=2,
        )
    )


###################################################################################################
if __name__ == '__main__':
    main()
