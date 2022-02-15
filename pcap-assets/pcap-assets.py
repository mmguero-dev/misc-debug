#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import itertools
import logging
import os
import sys
import ipaddress
import netaddr
import json

from scapy.all import *
from collections import namedtuple

import mmguero

###################################################################################################
args = None
script_name = os.path.basename(__file__)
script_path = os.path.dirname(os.path.realpath(__file__))
orig_path = os.getcwd()

Host = namedtuple("Host", ["mac", "ip"])

###################################################################################################
# main
def main():
    global args

    parser = argparse.ArgumentParser(
        description='\n'.join(
            [
                'Do some stuff.',
            ]
        ),
        formatter_class=argparse.RawTextHelpFormatter,
        add_help=False,
        usage='{} <arguments>'.format(script_name),
    )
    parser.add_argument('--verbose', '-v', action='count', default=1, help='Increase verbosity (e.g., -v, -vv, etc.)')
    parser.add_argument(
        '--ipv6',
        dest='ipv6',
        action='store_true',
        help='Extract IPv6 addresses',
    )
    parser.add_argument(
        '--no-ipv6',
        dest='ipv6',
        action='store_false',
        help='Do not extract IPv6 addresses (default)',
    )
    parser.set_defaults(ipv6=False)
    parser.add_argument(
        '--ipv4',
        dest='ipv4',
        action='store_true',
        help='Extract IPv4 addresses (default)',
    )
    parser.add_argument(
        '--no-ipv4',
        dest='ipv4',
        action='store_false',
        help='Do not extract IPv4 addresses',
    )
    parser.set_defaults(ipv4=True)
    parser.add_argument(
        '-i',
        '--input',
        dest='input',
        nargs='*',
        type=str,
        default=None,
        required=False,
        help="Input value(s)",
    )
    try:
        parser.error = parser.exit
        args = parser.parse_args()
    except SystemExit:
        parser.print_help()
        exit(2)

    args.verbose = logging.CRITICAL - (10 * args.verbose) if args.verbose > 0 else 0
    logging.basicConfig(
        level=args.verbose, format='%(asctime)s %(levelname)s: %(message)s', datefmt='%Y-%m-%d %H:%M:%S'
    )
    logging.debug(os.path.join(script_path, script_name))
    logging.debug("Arguments: {}".format(sys.argv[1:]))
    logging.debug("Arguments: {}".format(args))
    if args.verbose > logging.DEBUG:
        sys.tracebacklimit = 0

    IP.payload_guess = []

    ipv4Pairs = list()
    ipv6Pairs = list()

    for file in args.input:
        for p in PcapReader(file):
            if Ether in p:
                if args.ipv4 and (IP in p):
                    ipv4Pairs.append(
                        sorted(
                            [
                                Host(
                                    netaddr.EUI(p[Ether].src),
                                    ipaddress.ip_address(p[IP].src),
                                ),
                                Host(
                                    netaddr.EUI(p[Ether].dst),
                                    ipaddress.ip_address(p[IP].dst),
                                ),
                            ]
                        )
                    )
                elif args.ipv6 and (IPv6 in p):
                    ipv6Pairs.append(
                        sorted(
                            [
                                Host(
                                    netaddr.EUI(p[Ether].src),
                                    ipaddress.ip_address(p[IPv6].src),
                                ),
                                Host(
                                    netaddr.EUI(p[Ether].dst),
                                    ipaddress.ip_address(p[IPv6].dst),
                                ),
                            ]
                        )
                    )

    if args.ipv4:
        ipv4Pairs = [i for i, _ in itertools.groupby(sorted(ipv4Pairs))]
        for pair in ipv4Pairs:
            logging.debug(pair)

    if args.ipv6:
        ipv6Pairs = [j for j, _ in itertools.groupby(sorted(ipv6Pairs))]
        for pair in ipv6Pairs:
            logging.debug(pair)


###################################################################################################
if __name__ == '__main__':
    main()
