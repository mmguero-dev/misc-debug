#!/usr/bin/env bash

# one may wish to consider not using self-signed certificates in production
openssl dhparam -out dhparam.pem 2048
openssl req -subj '/CN=localhost' -x509 -newkey rsa:4096 -nodes -keyout key.pem -out cert.pem -days 3650
