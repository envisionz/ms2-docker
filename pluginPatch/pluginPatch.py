#!/usr/bin/env python3

from typing import Any, Optional, TextIO, List, Dict, Union
from enum import Enum, auto

import argparse
import json
from sys import exit

ALL_MODES = ['mobile', 'desktop', 'common', 'maps', 'dashboard', 'embedded', 'geostory-embedded',
             'dashboard-embedded', 'geostory', 'context-creator', 'manager', 'context-manager']


class PatchAction(Enum):
    ADD = auto()
    REMOVE = auto()
    REPLACE = auto()


def _get_modes(plugin: Dict[str, Any]) -> List[str]:
    mode = plugin['modes']
    if isinstance(mode, str) and mode == 'all':
        apply_modes = ALL_MODES
    else:
        apply_modes = mode
    return apply_modes


def _get_name(obj: Union[Dict, str]) -> str:
    if isinstance(obj, str):
        return obj
    else:
        return obj['name']


def _find_plugin_indices(plugins: List[Any], name: str) -> List[int]:
    indices = []
    for ind, p in enumerate(plugins):
        n = _get_name(p)
        if n == name:
            indices.append(ind)
    return indices


def patch_localconfig(action: PatchAction, cfg_plugins: Dict[str, List], patches: List[Dict[str, Any]]):
    for patch in patches:
        apply_modes = _get_modes(patch)
        for m in apply_modes:
            name = _get_name(patch['value'])
            indices = _find_plugin_indices(cfg_plugins[m], name)

            if action == PatchAction.ADD:
                cfg_plugins[m].append(patch['value'])

            elif action == PatchAction.REMOVE:
                for i in sorted(indices, reverse=True):
                    del cfg_plugins[m][i]
            
            elif action == PatchAction.REPLACE:
                for i in indices:
                    cfg_plugins[m][i] = patch['value']


def patch_config(in_lc_file: TextIO, out_lc_file: TextIO, patch_file: TextIO) -> bool:
    lc = json.load(in_lc_file)
    patch = json.load(patch_file)

    # Ensure that we have a localConfig file with the expected keys
    if 'plugins' not in lc:
        print('localConfig file has no "plugin" key')
        return False
    for p in ALL_MODES:
        if p not in lc['plugins']:
            print(f'plugins object has no "{p}" key')
            return False

    # Ensure patch file has 'plugins' key
    if 'plugins' not in patch:
        print('patch file has no "plugin" key')
        return False
    
    # Patch localConfig
    patch_plugins = patch['plugins']
    config_plugins = lc['plugins']
    if 'add' in patch_plugins:
        patch_localconfig(PatchAction.ADD, config_plugins, patch_plugins['add'])
    
    if 'remove' in patch_plugins:
        patch_localconfig(PatchAction.REMOVE, config_plugins, patch_plugins['remove'])
    
    if 'replace' in patch_plugins:
        patch_localconfig(PatchAction.REPLACE, config_plugins, patch_plugins['replace'])

    # Write new localConfig.json
    json.dump(lc, out_lc_file, indent=4, ensure_ascii=False)
    return True

def main():
    parser = argparse.ArgumentParser(
        description='Patch mapstore plugins config.')
    parser.add_argument(
        'input_lc_path', help='Path to the localConfig.json file')
    parser.add_argument(
        'output_lc_path', help='Path to the localConfig.json file')
    parser.add_argument('patch_path', help='Path to the patch file to apply')
    args = parser.parse_args()

    with open(args.input_lc_path, 'r') as in_lc_file, open(args.output_lc_path, 'w+') as out_lc_file, open(args.patch_path, 'r') as patch_file:
        res = patch_config(in_lc_file, out_lc_file, patch_file)
    
    if not res:
        exit(1)

if __name__ == '__main__':
    main()
