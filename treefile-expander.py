#!/bin/python3
# Author: Patrick Uiterwijk <patrick@puiterwijk.org>
# This code is released under CC0
# Do whatever you want with it
#
# This script takes an rpm-ostree tree file, and expands
# all of the @groups in it.

import os
import libcomps
import librepo
import sys
import json
import tempfile

if len(sys.argv) != 2:
    print('Run as: python treefile-expander.py <treefile>.json.in')
    sys.exit(1)

in_filename = sys.argv[1]
out_filename = sys.argv[1].replace('.in', '')
if os.path.exists(out_filename):
    print('%s exists' % out_filename)
    sys.exit(1)

contents = {}
with open(in_filename, 'r') as f:
    contents = json.loads(f.read())


def dl_callback(data, total_to_download, downloaded):
    PROGRESSBAR_LEN = 50
    """Progress callback"""
    if total_to_download <= 0:
        return
    completed = int(downloaded / (total_to_download / PROGRESSBAR_LEN))
    print("[%s%s] %8s/%8s (%s)\r" %
          ('#'*completed,
           '-'*(PROGRESSBAR_LEN-completed),
           int(downloaded),
           int(total_to_download),
           data),)
    sys.stdout.flush()


def include_package(pkg):
    if pkg.basearchonly and pkg.basearchonly != 'x86_64':
        return False

    if pkg.type == libcomps.PACKAGE_TYPE_OPTIONAL:
        # Could be set to True if you want optionals
        return False

    return True


tempdir = './temp'
with tempfile.TemporaryDirectory('treefile_') as tempdir:
    repos = {}
    print('Grabbing repo data')
    for repo in contents['repos']:
        print('Grabbing %s' % repo)
        with open('%s.repo' % repo, 'r') as repodata:
            os.mkdir('%s/%s' % (tempdir, repo))
            h = librepo.Handle()
            h.setopt(librepo.LRO_DESTDIR, '%s/%s' % (tempdir, repo))
            r = librepo.Result()
            got_link = False

            for line in repodata.readlines():
                if not line.startswith('#'):
                    if line.startswith('baseurl'):
                        url = line.split('=')[1].strip()
                        url = url.replace('$basearch', 'x86_64')
                        h.setopt(librepo.LRO_URLS, [url])
                        got_link = True
                    elif line.startswith('mirrorlist'):
                        url = line.split('=')[1].strip()
                        url = url.replace('$basearch', 'x86_64')
                        h.setopt(librepo.LRO_LRO_MIRRORLIST, url)
                        got_link = True

            if not got_link:
                print('Unable to find link')
                sys.exit(1)

            h.setopt(librepo.LRO_REPOTYPE, librepo.LR_YUMREPO)
            h.setopt(librepo.LRO_CHECKSUM, True)
            h.setopt(librepo.LRO_PROGRESSCB, dl_callback)
            h.setopt(librepo.LRO_YUMDLIST, ["group"])
            h.setopt(librepo.LRO_INTERRUPTIBLE, True)
            h.perform(r)

            # We only want the comps info
            comps = libcomps.Comps()
            ret = comps.fromxml_f(r.getinfo(librepo.LRR_YUM_REPO)['group'])
            if ret == -1:
                print('Error parsing')
            else:
                repos[repo] = comps

    expanded = 0
    in_packages = contents['packages']
    out_packages = set()
    for package in in_packages:
        if package.startswith('@'):
            # Evaluate
            package = package[1:]
            expanded += 1
            found = False
            for repo in repos:
                comp = repos[repo]
                try:
                    group = comp.groups[package]
                    found = True
                    added_packages = 0
                    skipped_packages = 0
                    for pkg in group.packages:
                        if include_package(pkg):
                            added_packages += 1
                            out_packages.add(pkg.name)
                        else:
                            skipped_packages = 1
                    print('Group %s was expanded to %d (skipped %d)' %
                          (package,
                           added_packages,
                           skipped_packages))
                except KeyError:
                    # Seems this group was not in this file
                    pass
            if not found:
                print('Group %s could not be expanded' % package)
                sys.exit(1)
        else:
            out_packages.add(package)
    contents['packages'] = list(out_packages)

with open(out_filename, 'w') as f:
    f.write(json.dumps(contents,
                       sort_keys=True,
                       indent=4,
                       separators=(',', ': ')))

print('Wrote %s after expanding %d groups' % (out_filename, expanded))
