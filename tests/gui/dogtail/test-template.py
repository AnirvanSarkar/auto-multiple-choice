#! /usr/bin/env python3

# GUI test for templates, part 1

import amc
import os

a = amc.AMC()
a.launch()

a.open_project('a ccentué', 'test-template')
a.build_documents()
a.build_other_document(2)
a.scan_from_individual_solution(dest="template-3.pdf")

a.create_template('déjà fait', with_files=['東京.txt'])

if not os.path.isfile(a.template_file('déjà fait')):
    raise ValueError("Built template not found")

a.finished()

