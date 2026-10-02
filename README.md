# MPC-HC, buildable from GitHub alone

Upstream [clsid2/mpc-hc](https://github.com/clsid2/mpc-hc) cannot be cloned
recursively from networks that block gitea.1f0.de, because LAV Filters pulls
libbluray and qsdecoder from there. This repo is a copy where every one of those
submodules comes from GitHub.

    git clone -b develop --recursive https://github.com/adipose/mpc-hc-github.git

The `develop` branch is upstream's `develop` with one change: the LAV Filters
submodule points at
[adipose/LAVFilters](https://github.com/adipose/LAVFilters/tree/github-submodules)
`github-submodules`. That branch is the LAV commit upstream pins, with its gitea
submodules pointed at the mirrors
[adipose/libbluray](https://github.com/adipose/libbluray) and
[adipose/qsdecoder](https://github.com/adipose/qsdecoder). No source is changed
anywhere.

A [daily workflow](.github/workflows/sync.yml) runs [sync.sh](sync.sh) to pull
in upstream changes. Every derived commit keeps the upstream commit as a parent,
so the branches only move forward and upstream history is all there.

This `sync` branch holds only the workflow. It is the default branch so that
the schedule runs.
