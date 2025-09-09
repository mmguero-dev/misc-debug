#!/usr/bin/env python3

from dateparser import parse as ParseDate
from datetime import datetime, timezone
import argparse
import asyncio
import json
import sys
import vt

# Keep a reference to the original vt-py Client get_async method
_original_get_async = vt.Client.get_async


async def debug_get_async(self, path: str, *path_args, params=None, **kwargs):
    # Log the outgoing request
    print(f"[VT DEBUG] GET {path} {path_args} params={params} kwargs={kwargs}", file=sys.stderr)
    # Call the original method and return its result
    return await _original_get_async(self, path, *path_args, params=params, **kwargs)


# Patch the class method
vt.Client.get_async = debug_get_async


# Iterate through the /collections list, filtering by collection type and ordering by last_modification_date
#   descending, then short-circuit when we've gotten older than our specified "after" window
def iter_collections(client, ctype="report", after=None, before=None):
    for collection in client.iterator(
        "/collections",
        params={
            "filter": f"collection_type:{ctype}",
            "order": "last_modification_date-",
        },
    ):
        created_ts = collection.get("creation_date")
        created = datetime.fromtimestamp(created_ts).astimezone(timezone.utc) if created_ts else None
        modified_ts = collection.get("last_modification_date")
        modified = datetime.fromtimestamp(modified_ts).astimezone(timezone.utc) if modified_ts else created

        if created and modified:
            if after and created < after and modified < after:
                break
            if before and created > before and modified > before:
                continue

        yield collection


def main():
    parser = argparse.ArgumentParser(description="List IoC Collections")
    parser.add_argument(
        "--apikey",
        required=True,
        help="your VirusTotal API key",
    )
    parser.add_argument(
        "--ctype",
        required=False,
        default="report",
        help="Collection type",
    )
    parser.add_argument(
        '--download',
        action='store_true',
        required=False,
        default=False,
        help='Call `get_object` for the /download endpoint for a collection (takes precedence over --object)',
    )
    parser.add_argument(
        '--object',
        action='store_true',
        required=False,
        default=False,
        help='Call `get_object` for collection',
    )
    parser.add_argument(
        '--verbose',
        action='store_true',
        required=False,
        default=False,
        help='Dump collection details',
    )
    parser.add_argument(
        '--after',
        dest='after',
        type=str,
        default="48 hours ago",
        help="Retrieve indicators after this time (e.g., '48 hours ago')",
    )
    parser.add_argument(
        '--before',
        dest='before',
        type=str,
        default="24 hours ago",
        help="Retrieve indicators before this timestamp (e.g., '24 hours ago')",
    )
    parser.add_argument(
        '--limit',
        dest='limit',
        type=int,
        default=0,
        help="Maximum number of collections to retrieve (0 = no limit)",
    )
    args = parser.parse_args()

    with vt.Client(args.apikey) as client:
        try:
            count = 0
            for collection in iter_collections(
                client,
                args.ctype,
                after=(
                    ParseDate(args.after).astimezone(timezone.utc)
                    if (args.after is not None) and (len(args.after) > 0)
                    else None
                ),
                before=(
                    ParseDate(args.before).astimezone(timezone.utc)
                    if (args.before is not None) and (len(args.before) > 0)
                    else None
                ),
            ):
                if args.download:
                    iocDownload = client.get_json(f"/collections/{collection.id}/download/json")
                    if isinstance(iocDownload, dict):
                        if args.verbose:
                            print(json.dumps({"id": collection.id} | iocDownload))
                        elif isinstance(iocDownload, dict):
                            print(json.dumps({"id": collection.id} | {k: len(v) for k, v in iocDownload.items()}))
                    else:
                        print(json.dumps(iocDownload))
                elif args.object:
                    collectionDetails = client.get_object(f"/collections/{collection.id}")
                    if args.verbose:
                        print(json.dumps(collectionDetails.to_dict()))
                    else:
                        print(json.dumps({"id": collectionDetails.id}))
                else:
                    if args.verbose:
                        print(json.dumps(collection.to_dict()))
                    else:
                        print(json.dumps({"id": collection.id}))
                count += 1
                if args.limit > 0 and count >= args.limit:
                    break

        except KeyboardInterrupt:
            print("\nKeyboard interrupt", file=sys.stderr)


if __name__ == "__main__":
    main()
