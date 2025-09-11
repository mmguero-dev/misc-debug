#!/usr/bin/env python3

from dateparser import parse as ParseDate
from datetime import datetime, timezone
import argparse
import asyncio
import json
import os
import sys
import time
import vt

debug_gets = False

# Keep a reference to the original vt-py Client get_async method
_original_get_async = vt.Client.get_async


async def debug_get_async(self, path: str, *path_args, params=None, **kwargs):
    if debug_gets:
        # Log the outgoing request
        print(f"[VT DEBUG] GET {path} {path_args} params={params} kwargs={kwargs}", file=sys.stderr)
    # Call the original method and return its result
    return await _original_get_async(self, path, *path_args, params=params, **kwargs)


# Patch the class method
vt.Client.get_async = debug_get_async


# Iterate through the /collections list, filtering by collection type and ordering by last_modification_date
#   descending, then short-circuit when we've gotten older than our specified "since" window
def iter_google_collections_since(
    client,
    ctypes=[
        'report',
        'campaign',
        'threat-actor',
        'malware-family',
    ],
    filters=None,
    since=None,
):
    # https://gtidocs.virustotal.com/reference/list-threats
    # https://gtidocs.virustotal.com/reference/ioc-collection-object
    searchFilter = "(" + " OR ".join(f'collection_type:"{c}"' for c in ctypes) + ")"
    if filters:
        searchFilter += f" AND ({filters})"

    while True:
        try:
            for collection in client.iterator(
                "/collections",
                params={
                    "filter": searchFilter,
                    # sort by last modification date descending, so we can short-circuit based on "since"
                    "order": "last_modification_date-",
                },
            ):
                created_ts = collection.get("creation_date")
                created = datetime.fromtimestamp(created_ts).astimezone(timezone.utc) if created_ts else None
                modified_ts = collection.get("last_modification_date")
                modified = datetime.fromtimestamp(modified_ts).astimezone(timezone.utc) if modified_ts else None
                created, modified = created or modified, modified or created

                if since and created and modified and created < since and modified < since:
                    # short-circuit due to going beyond our "since" window
                    break

                yield collection

            break  # finished cleanly

        except vt.error.APIError as e:
            # Retry only on server-side failures
            if getattr(e, "code", None) == "ServerError":
                print(f"[VT ERROR] 500 Server Error, retrying in 1s...", file=sys.stderr)
                time.sleep(1)
                continue
            else:
                raise


def main():
    global debug_gets

    parser = argparse.ArgumentParser(description="List IoC Collections")
    parser.add_argument(
        "-a",
        "--apikey",
        required=True,
        help="your VirusTotal API key",
    )
    parser.add_argument(
        "--agent",
        required=False,
        default=os.path.basename(__file__),
        help="Agent string for client",
    )
    parser.add_argument(
        '-c',
        '--ctype',
        dest='ctypes',
        nargs='*',
        type=str,
        default=[
            'report',
            'campaign',
            'threat-actor',
            'malware-family',
        ],
        help="Collection types",
    )
    parser.add_argument(
        '-f',
        '--filter',
        dest='filters',
        type=str,
        default=None,
        help="Additional filters",
    )
    parser.add_argument(
        '-d',
        '--download',
        action='store_true',
        required=False,
        default=False,
        help='Call `get_object` for the /download endpoint for a collection ()',
    )
    parser.add_argument(
        '-o',
        '--object',
        action='store_true',
        required=False,
        default=False,
        help='Call `get_object` for collection',
    )
    parser.add_argument(
        '--debug',
        action='store_true',
        required=False,
        default=False,
        help='Debug HTTP gets',
    )
    parser.add_argument(
        '-v',
        '--verbose',
        action='store_true',
        required=False,
        default=False,
        help='Dump collection dict',
    )
    parser.add_argument(
        '-s',
        '--since',
        dest='since',
        type=str,
        default="48 hours ago",
        help="Retrieve indicators since this time (e.g., '48 hours ago')",
    )
    parser.add_argument(
        '-l',
        '--limit',
        dest='limit',
        type=int,
        default=0,
        help="Maximum number of collections to retrieve (0 = no limit)",
    )
    args = parser.parse_args()

    debug_gets = args.debug

    with vt.Client(
        args.apikey,
        agent=args.agent,
    ) as client:
        try:
            count = 0
            for collection in iter_google_collections_since(
                client,
                ctypes=args.ctypes,
                filters=args.filters,
                since=(
                    ParseDate(args.since).astimezone(timezone.utc)
                    if (args.since is not None) and (len(args.since) > 0)
                    else None
                ),
            ):
                try:
                    if args.download:
                        iocDownload = client.get_json(f"/collections/{collection.id}/download/json")
                        if isinstance(iocDownload, dict):
                            if args.verbose:
                                print(json.dumps({"id": collection.id, "name": collection.name} | iocDownload))
                            elif isinstance(iocDownload, dict):
                                print(
                                    json.dumps(
                                        {"id": collection.id, "name": collection.name}
                                        | {k: len(v) for k, v in iocDownload.items()}
                                    )
                                )
                        else:
                            print(json.dumps(iocDownload))
                    elif args.object:
                        collectionDetails = client.get_object(f"/collections/{collection.id}")
                        if args.verbose:
                            print(json.dumps(collectionDetails.to_dict()))
                        else:
                            print(json.dumps({"id": collectionDetails.id, "name": collectionDetails.name}))
                    else:
                        if args.verbose:
                            print(json.dumps(collection.to_dict()))
                        else:
                            print(json.dumps({"id": collection.id, "name": collection.name}))
                    count += 1
                    if args.limit > 0 and count >= args.limit:
                        break
                except vt.error.APIError as e:
                    print(
                        f"[VT ERROR] Error processing {collection.id} ({collection.name}) {e.code}: {e.message}",
                        file=sys.stderr,
                    )
                    if getattr(e, "code", None) == "ServerError":
                        # Continue only on server-side failures
                        time.sleep(1)
                    else:
                        continue

        except KeyboardInterrupt:
            print("\nKeyboard interrupt", file=sys.stderr)


if __name__ == "__main__":
    main()
