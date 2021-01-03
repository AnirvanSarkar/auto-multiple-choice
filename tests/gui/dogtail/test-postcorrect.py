#! /usr/bin/env python3

# GUI test from a zip archive, with postcorrection and manual association

import amc

a = amc.AMC()

a.launch()
a.new_project_from_archive('test-postcorrect/saved.zip')
a.copy_in_src_dir('test-postcorrect/scan-0.tiff')
a.copy_in_src_dir('test-postcorrect/scan-1.tiff')
a.auto_data_capture(files=['scan-0.tiff', 'scan-1.tiff'])
a.mark()
a.postcorrect(2,0)
a.add_files_to_project('test-postcorrect/people.csv')
a.set_students_list('people.csv', auto=False, uid='student')
a.manual_association(['Teacher','Jojo'])
a.report(output_format='CSV')
a.check_csv_results({"3": { "Mark": "12,5", "Name": "Jojo" }})

a.finished()
