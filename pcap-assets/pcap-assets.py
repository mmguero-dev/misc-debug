#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import itertools
import logging
import os
import sys
from socket import inet_aton
import struct

from scapy.all import *

import mmguero

###################################################################################################
args = None
script_name = os.path.basename(__file__)
script_path = os.path.dirname(os.path.realpath(__file__))
orig_path = os.getcwd()

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
        help='Extract IPv6 addresses (default: IPv4)',
    )
    parser.add_argument(
        '--no-ipv6',
        dest='ipv6',
        action='store_false',
        help='Do not extract IPv6 addresses (default)',
    )
    parser.set_defaults(ipv6=False)
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

    ipv4 = sorted(
        list(
            set(itertools.chain(*[(p[IP].dst, p[IP].src) for file in args.input for p in PcapReader(file) if IP in p]))
        ),
        key=lambda ip: struct.unpack("!L", inet_aton(ip))[0],
    )
    logging.debug(ipv4)


###################################################################################################
if __name__ == '__main__':
    main()
