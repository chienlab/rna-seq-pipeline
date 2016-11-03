#!/usr/bin/python
import sys
import xml.etree.cElementTree as etree

_tree = None

def show_usage():
    print('''
Usage:
./query_dataset.py QUERY [ARGUMENT] DATASET.xml

QUERY       ARGUMENT        RESULT
groups      none            IDs of all groups of samples or pairs
group       sample/pair ID  ID of the given sample's group
samples     [group ID]      Sample IDs (all or just in a given group)
sampledirs  [group ID]      Sample dirs, or IDs where no dir is defined
sampledir   sample ID       Sample directory of the given sample
siblings    sample ID       Sample IDs in the same group as the given sample
    ''')
    exit(1)

def main():
    global _tree

    arg_count = len(sys.argv) - 1
    if arg_count < 2 or 3 < arg_count:
        show_usage()

    query_name = sys.argv[1]
    query_arg = sys.argv[2] if arg_count > 2 else ''
    list_file = sys.argv[-1]

    _tree = etree.parse(list_file)


    elif query_name == 'groups':
        print_all_groups()

    elif query_name == 'group':
        if not query_arg:
            print('ERROR - "group" query requires sample ID argument')
            exit(1)
        print_group_for_sample(query_arg)

    elif query_name == 'samples':
        if query_arg:
            print_samples_for_group(query_arg)
        else:
            print_all_samples()

    elif query_name == 'sampledirs':
        if query_arg:
            print_sample_dirs_for_group(query_arg)
        else:
            print_all_sample_dirs()

    elif query_name == 'sampledir':
        if not query_arg:
            print('ERROR - "sampledir" query requires sample ID argument')
            exit(1)
        print_dir_for_sample(query_arg)

    elif query_name == 'siblings':
        if not query_arg:
            print('ERROR - "siblings" query requires sample ID argument')
            exit(1)
        print_siblings_for_sample(query_arg)

    else:
        show_usage()

#----------------------------------------------
# QUERY: groups
#----------------------------------------------

def print_all_groups():
    for group in get_group_nodes():
        print(group.get('id'))

#----------------------------------------------
# QUERY: group
#----------------------------------------------

def print_group_for_sample(sample_id):
    group = get_group_for_sample(sample_id)
    if group:
        print group.get('id')

#----------------------------------------------
# QUERY: samples
#----------------------------------------------

def print_all_samples():
    for sample in get_sample_nodes():
        print(sample.get('id'))

def print_samples_for_group(group_id):
    for sample in get_group(group_id):
        print(sample.get('id'))

#----------------------------------------------
# QUERY: sampledirs
#----------------------------------------------

def print_all_sample_dirs():
    for sample in get_sample_nodes():
        print_dir_or_id(sample)

def print_sample_dirs_for_group(group_id):
    for sample in get_group(group_id):
        print_dir_or_id(sample)

#----------------------------------------------
# QUERY: sampledir
#----------------------------------------------

def print_dir_for_sample(sample_id):
    for sample in get_sample_nodes():
        if sample.get('id') == sample_id:
            print_dir_or_id(sample)
            return

#----------------------------------------------
# QUERY: siblings
#----------------------------------------------

def print_siblings_for_sample(sample_id):
    group = get_group_for_sample(sample_id)
    if group:
        print_samples_for_group(group.get('id'))

#----------------------------------------------
# HELPERS
#----------------------------------------------

def print_dir_or_id(sample):
    dir = sample.get('dir')
    if dir:
        print(dir)
    else:
        print(sample.get('id'))

def get_group(id):
    for group in get_group_nodes():
        if group.get('id') == id:
            return group
    return []

def get_group_for_sample(sample_id):
    for group in get_group_nodes():
        for sample in group:
            if sample.get('id') == sample_id:
                return group
    return None

def get_group_nodes():
    return _tree.findall('.//group')

def get_sample_nodes():
    return _tree.findall('.//sample')

if __name__ == '__main__':
    main()
