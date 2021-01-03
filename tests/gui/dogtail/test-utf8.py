#! /usr/bin/env python3

# GUI test with UTF8 characters in file names

import amc

a = amc.AMC()
a.project_name = 'Œufs durs'
a.src_dirname = 'Les sources des Œufs'
a.print_subdir = '試験'

a.launch()
a.new_project_from_file('src-utf8/TEST Œufs.tex')
a.add_files_to_project('src-utf8/students.csv')
a.build_documents()
a.build_other_document(2)
a.print_to_file(copies=[2])
a.scan_from_blank_copy(dest='スキャン.jpg')
a.scan_from_individual_solution(pages=[3], dest='świetny 3.pdf')
a.auto_data_capture(files=['スキャン.jpg', 'świetny 3.pdf'])
a.mark()
a.set_students_list('students.csv')
a.set_options(description=['L\'examen des œufs durs !', 'Œufs durs'])
a.report()
a.report(output_format='CSV')
a.annotate(model='(id) ŒD (ID)')
a.check_csv_results({"2": {"A:id": "902",
                           "Name": "André Golin", "Mark": "0"},
                     "3": {"A:id": "903",
                           "Name": "Stanisław Moniuszko", "Mark": "20"},
                     })
a.check_annotated_files_exist('902 ŒD André Golin.pdf',
                              '903 ŒD Stanisław Moniuszko.pdf')

a.finished()
