#! /usr/bin/env python3

# GUI test for barcodes in the name field.

import amc

a = amc.AMC()

a.launch()
a.open_project('test', 'test-barcode')
a.build_documents()
a.copy_in_src_dir('test-barcode/copie-1.tiff')
a.copy_in_src_dir('test-barcode/copie-2.tiff')
a.auto_data_capture(files=['copie-1.tiff', 'copie-2.tiff'])
a.mark()
a.add_files_to_project('test-barcode/students.txt')
a.set_students_list('students.txt',
                    uid='code',code='Decoded name field')
a.report(output_format='CSV')
a.check_csv_results({"1": { "A:code": "0214568-0786",
                            "Name": "Ex Complet"},
                     "4": { "A:code": "http://en.m.wikipedia.org",
                            "Name": "QRcode complet"}})
a.set_options(namefield='Barcode tail')
a.auto_association()
a.report(output_format='CSV')
a.check_csv_results({"1": { "A:code": "0786",
                            "Name": "Ex Court"},
                     "4": { "A:code": "org",
                            "Name": "QRcode court"}})

a.finished()
