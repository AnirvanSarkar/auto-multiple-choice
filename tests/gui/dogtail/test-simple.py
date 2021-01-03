#! /usr/bin/env python3

# GUI test from a standard template, with photocopy mode

import amc

a = amc.AMC()

a.launch()
a.new_project_from_template()
a.build_documents()
a.copy_in_src_dir('test-simple/1.jpg')
a.copy_in_src_dir('test-simple/2.tif')
a.auto_data_capture(files=['1.jpg', '2.tif'],
                    prealloc=True,
                    mode='Some answer sheets were photocopied')
a.mark()
a.set_options()
a.report(output_format='CSV')
a.check_csv_results({"3:1": { "Mark": "5",  "pref": "1", "prez": "0" },
                     "3:2": { "Mark": "20", "pref": "3", "prez": "1" },
                     })

a.finished()
