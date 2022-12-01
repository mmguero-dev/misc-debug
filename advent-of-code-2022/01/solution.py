#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys

with open(sys.argv[1], 'r') as f:
    elves = [x.split('\n') for x in f.read().split("\n\n")]

cals = sorted([sum([int(x) for x in y if x.isdigit()]) for y in elves])

print(cals[-1])
print(sum(cals[-3:]))
