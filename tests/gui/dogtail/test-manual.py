#! /usr/bin/env python3

# GUI test from a standard template, with photocopy mode

import amc

a = amc.AMC()

a.launch()
a.new_project_from_file('test-manual/source.txt')
a.build_documents()
for i in [1,2,3]:
    a.copy_in_src_dir("test-manual/p-%d.jpg" % i)
a.auto_data_capture(files=['p-1.jpg', 'p-2.jpg', 'p-3.jpg'],
                    prealloc=True,
                    mode='Some answer sheets were photocopied')
a.mark()
a.report(output_format='CSV', options_cb=[(1,'Yes: AB')])
a.check_csv_results({"3:1": { "TICKED:points":"CF" },
                     "3:2": { "TICKED:points":"AF" },
                     "3:3": { "TICKED:points":"AEF" }})

# Some manual data capture for copy 1
a.edit_with_zooms("3/1:1", check=[5], uncheck=[3])
a.report(output_format=None)
a.check_csv_results({"3:1": { "TICKED:points":"DF" }})

# cancel manual data capture
a.cancel_manual_data_capture("3/1:1")
a.report(output_format=None)

# Edit with zooms, but cancel
a.edit_with_zooms("3/1:1", check=[1,2,3,4], uncheck=[6], save=False)
a.check_csv_results({"3:1": { "TICKED:points":"CF" }})

# Edit with manual data capture
a.manual_data_capture("3/1:2", 3, [(1,1), (1,2), (1,3)])
a.report(output_format=None)
a.check_csv_results({"3:2": { "TICKED:points":"BCF" }})

a.finished()
