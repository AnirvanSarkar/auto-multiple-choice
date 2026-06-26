#! /usr/bin/env python3

import amc

import os
import time

a = amc.AMC()
a.shortcode = 'MultiCopies'

a.launch()
a.open_project('multicop', 'test-multicopies')
a.build_documents()

for d in os.listdir('test-multicopies-scans'):
    a.copy_in_src_dir(f'test-multicopies-scans/{d}')

a.auto_data_capture(files=['00-6.png', '10-1.png', '11-7.png'])
time.sleep(1)
a.auto_data_capture(files=['20-8.png', '30-3.png', '50-5.png'])
time.sleep(2)

a.manual_data_capture("2/1", 2, clicks=[(3,5), (3,6)])

a.mark()
a.set_students_list('students.csv',
                    uid='id', code='student.number')

a.manual_data_capture("6/1", 6, clicks=[(3,1), (3,2)])
a.mark()

a.force_manual_association(sequence=[('2', 'Jojo (1)'),('8', 'Jojo (2)')])

a.report(output_format='CSV')
a.check_csv_results({"6": { "version": "1" },
                     "8": { "version": "2" },
                     "2": { "version": "3" },
                     })

a.annotate_selected(nrows=7, sort_by=[("exam ID", 1), ("student", 1)],
                    selected=[{"version": 3}])
a.check_annotated_files_exist(('0002-Jojo-v3.pdf', '[2] Jojo v3'))

a.annotate(model='(ID).(version)')
a.check_annotated_files_exist(
    ('Jojo.1.pdf', '[6] Jojo'),
    ('Jojo.2.pdf', '[8] Jojo v2'),
    ('Jojo.3.pdf', '[2] Jojo v3'),
    ('Douze.1.pdf', '[1] Douze'),
    ('Six.1.pdf', '[7] Six'),
    ('Claire.1.pdf', '[3] Claire'),
    ('Pil.1.pdf', '[5] Pil'),
    )

a.set_options(description=None, mail_store=True)
a.send_mail(nrows=7, sort_by=[("version", 2)], row={"name": "Jojo", "version": 3})
a.check_annotated_files_exist(('corrected.pdf', '[2] Jojo v3'), attachments=True)

a.finished()
