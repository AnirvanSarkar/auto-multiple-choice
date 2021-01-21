#! /usr/bin/env python3

# GUI test from printing with cups

import amc

a = amc.AMC()

a.launch()
a.new_project_from_file('test-cups/source.txt')
a.build_documents()
a.set_options(printing_method = "CUPS")
empty = a.print_to_cups([2])
a.auto_data_capture(files=empty)
a.mark()
a.report(output_format='CSV')
a.check_csv_results({"2": { "Mark": "0" }})

a.finished()
