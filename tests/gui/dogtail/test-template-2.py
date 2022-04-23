#! /usr/bin/env python3

# GUI test for templates, part 2

import amc

b = amc.AMC()
b.project_name = 'reprisé'
b.launch(delete_sources=False)

b.new_project_from_template(section=None, template='Template déjà fait')

file1 = open(b.project_dir() + '/東京.txt', "r")
s = file1.read()
file1.close()
if s != "Tokyo\n":
    raise ValueError('Wrong file content from template')

b.build_documents()
b.auto_data_capture(["template-3.pdf"])
b.mark()
b.report(output_format='CSV')
b.check_csv_results({"3": { "Mark": "20" }})

b.finished()
