#!/usr/bin/python
import sys
import xml.etree.cElementTree as etree

_root = None

def show_usage():
    print('''
Usage:
./query_dataset.py QUERY [ARGUMENT] DATASET.xml

QUERY       ARGUMENT      RESULT
patients    none          Prints patient IDs.
patient     sample ID     Prints patient ID for the given sample.
samples     [patient ID]  Prints sample IDs (can filter by a given patient).
sampledirs  [patient ID]  Prints sample dirs, or IDs where no dir is defined.
sampledir   sample ID     Prints sample directory of the given sample.
siblings    sample ID     Prints sample IDs for the patient of the given sample.
    ''')
    exit(1)

def main():
    global _root

    arg_count = len(sys.argv) - 1
    if arg_count < 2 or 3 < arg_count:
        show_usage()

    query_name = sys.argv[1]
    query_arg = sys.argv[2] if arg_count > 2 else ''
    list_file = sys.argv[-1]

    _root = etree.parse(list_file)

    if query_name == 'patients':
        print_all_patients()

    elif query_name == 'patient':
        if not query_arg:
            print('ERROR - "patient" query requires sample ID argument')
            exit(1)
        print_patient_for_sample(query_arg)

    elif query_name == 'samples':
        if query_arg:
            print_samples_for_patient(query_arg)
        else:
            print_all_samples()

    elif query_name == 'sampledirs':
        if query_arg:
            print_sample_dirs_for_patient(query_arg)
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
# QUERY: patients
#----------------------------------------------

def print_all_patients():
    for patient in get_patient_nodes():
        print(patient.get('id'))

#----------------------------------------------
# QUERY: patient
#----------------------------------------------

def print_patient_for_sample(sample_id):
    patient = get_patient_for_sample(sample_id)
    if patient:
        print patient.get('id')

#----------------------------------------------
# QUERY: samples
#----------------------------------------------

def print_all_samples():
    for sample in get_sample_nodes():
        print(sample.get('id'))

def print_samples_for_patient(patient_id):
    for sample in get_patient(patient_id):
        print(sample.get('id'))

#----------------------------------------------
# QUERY: sampledirs
#----------------------------------------------

def print_all_sample_dirs():
    for sample in get_sample_nodes():
        print_dir_or_id(sample)

def print_sample_dirs_for_patient(patient_id):
    for sample in get_patient(patient_id):
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
    patient = get_patient_for_sample(sample_id)
    if patient:
        print_samples_for_patient(patient.get('id'))

#----------------------------------------------
# HELPERS
#----------------------------------------------

def print_dir_or_id(sample):
    dir = sample.get('dir')
    if dir:
        print(dir)
    else:
        print(sample.get('id'))

def get_patient(id):
    for patient in get_patient_nodes():
        if patient.get('id') == id:
            return patient
    return []

def get_patient_for_sample(sample_id):
    for patient in get_patient_nodes():
        for sample in patient:
            if sample.get('id') == sample_id:
                return patient
    return None

def get_patient_nodes():
    global _root
    return _root.findall('.//patient')

def get_sample_nodes():
    global _root
    return _root.findall('.//sample')

if __name__ == '__main__':
    main()
