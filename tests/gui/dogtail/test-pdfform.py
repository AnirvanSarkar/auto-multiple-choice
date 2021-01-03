#! /usr/bin/env python3

# GUI test from an empty file, using password protected pdfform

import amc

a = amc.AMC()

with open('test-pdfform/essai.txt') as f:
    amc_txt = f.readlines()

a.launch()
a.new_project_from_text(text="".join(amc_txt))
a.build_documents()
a.print_to_file(copies=[1,2,3], password=True)
a.copy_in_src_dir('test-pdfform/sheet-0001.pdf')
a.copy_in_src_dir('test-pdfform/sheet-0002.pdf')
a.copy_in_src_dir('test-pdfform/sheet-0003.pdf')
a.auto_data_capture(files=['sheet-0001.pdf', 'sheet-0002.pdf', 'sheet-0003.pdf'])
a.mark()
a.report(output_format='CSV')
a.check_csv_results({"1": { "dosydos": "0", "francia": "1", "oceans": "0" },
                     "2": { "dosydos": "0", "francia": "0", "oceans": "4" },
                     "3": { "dosydos": "0", "francia": "0", "oceans": "-4" },
                     })

a.finished()
