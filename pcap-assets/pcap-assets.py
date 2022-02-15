#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import itertools
import logging
import math
import os
import sys
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


# function to find the position
# of rightmost set bit
def getPosOfRightmostSetBit(n):
    return round(math.log(((n & -n) + 1), 2))


# function to get the position ot rightmost unset bit
def getPosOfRightMostUnsetBit(n):
    # if n = 0, return 1
    if n == 0:
        return 1

    # if all bits of 'n' are set
    if (n & (n + 1)) == 0:
        return -1

    # position of rightmost unset bit in 'n'
    # passing ~n as argument
    return getPosOfRightmostSetBit(~n)


def guessSubnetCidr(hosts):
    numeric_hosts = [int(ip) for ip in sorted(hosts)]
    subnet_range = numeric_hosts[-1] - numeric_hosts[0]
    final_host = netaddr.IPAddress(numeric_hosts[-1])

    exponent = 0
    estimated_subnet_size = 1
    cidr = 32
    # if 2^x is less than the range of ip address and if the maximum proposed range is still lower than the highest ip address
    while ((2**exponent) < subnet_range) or (
        final_host not in netaddr.IPNetwork(f"{str(netaddr.IPAddress(numeric_hosts[0]))}/{cidr}")
    ):
        estimated_subnet_size = 2**exponent
        exponent = exponent + 1
        cidr = cidr - 1

    return cidr


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

    for file in args.input:
        for p in PcapReader(file):
            if (Ether in p) and (IP in p):
                ipv4Pairs.append(
                    sorted(
                        [
                            Host(
                                netaddr.EUI(p[Ether].src),
                                netaddr.IPAddress(p[IP].src),
                            ),
                            Host(
                                netaddr.EUI(p[Ether].dst),
                                netaddr.IPAddress(p[IP].dst),
                            ),
                        ]
                    )
                )

    ipv4Pairs = [i for i, _ in itertools.groupby(sorted(ipv4Pairs))]
    subnetsFromBroadcast = [
        subnet
        for subnet in sorted(
            list(
                set(
                    [
                        netaddr.IPNetwork(f"{x.ip}/{32 - ((getPosOfRightMostUnsetBit(int(x.ip)) // 8) * 8)}")
                        for x in list(itertools.chain(*ipv4Pairs))
                        if x.mac == netaddr.EUI('ff-ff-ff-ff-ff-ff') and x.ip != netaddr.IPAddress('255.255.255.255')
                    ]
                )
            )
        )
        if subnet.prefixlen > 0 and subnet.prefixlen < 32
    ]
    for subnet in subnetsFromBroadcast:
        logging.debug(subnet.cidr)

    guessed = guessSubnetCidr(x.ip for x in list(itertools.chain(*ipv4Pairs)))
    logging.debug(guessed)


###################################################################################################
if __name__ == '__main__':
    main()
