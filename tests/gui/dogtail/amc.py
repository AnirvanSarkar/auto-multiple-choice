
import os
import os.path
from shutil import copyfile, rmtree
import csv
import subprocess
import time

os.system('gsettings set org.gnome.desktop.interface toolkit-accessibility true')

import dogtail.tc
from dogtail.procedural import *
import dogtail.utils
from dogtail.predicate import GenericPredicate
from dogtail.tree import *

from gi.repository import Gdk
from pyatspi import Registry as registry
from pyatspi import (KEY_SYM, KEY_PRESS, KEY_PRESSRELEASE, KEY_RELEASE)


def keycodes(name):
    keymap = Gdk.Keymap.get_for_display(Gdk.Display.get_default())
    entries = keymap.get_entries_for_keyval(Gdk.keyval_from_name(name))
    return [key.keycode for key in entries[1]]


def code_to_names(code):
    keymap = Gdk.Keymap.get_for_display(Gdk.Display.get_default())
    entries = keymap.get_entries_for_keycode(code)
    return [Gdk.keyval_name(i) for i in entries[2]]


def code_to_firstname(code):
    names = code_to_names(code)
    if len(names) >= 1:
        return names[0]
    else:
        return None


def find_standard_code(name):
    for i in keycodes(name):
        if code_to_firstname(i) == name:
            return i
    return None


def test_codes():
    for i in range(100):
        print(i, code_to_names(i))


control_code = find_standard_code('Control_L')


class AMC:

    def __init__(self):
        self.gui = None
        self.tmp_dir = os.getenv("HOME") + '/AMC-tmp'
        self.cups_pdf_dir = os.getenv("HOME") + '/PDF'
        self.tmp_bookmark = 'AMC-tmp'
        self.project_name = 'test'
        self.debug = False
        self.src_dirname = 'sources'
        self.print_subdir = 'printed_copies'
        self.config_file = 'cf.xml'
        self.shortcode = None
        self.global_password = 'ABCDEF'
        self.password_column = 'id'
        self.amc_path = os.getenv("AMC_PATH")
        if not self.amc_path:
            self.amc_path = 'auto-multiple-choice'

    def amc_cmd(self):
        if self.debug:
            return self.amc_path + ' gui --debug --testing --profile TEST'
        else:
            return self.amc_path + ' gui --testing --profile TEST'

    def code(self):
        if self.shortcode:
            return self.shortcode
        else:
            return self.project_name

    def project_dir(self):
        return self.tmp_dir + '/' + self.project_name

    def src_dir(self):
        return self.tmp_dir + '/' + self.src_dirname

    def copy_in_src_dir(self, path):
        if not os.path.isdir(self.src_dir()):
            os.mkdir(self.src_dir())
        base = os.path.basename(path)
        copyfile(path, self.src_dir() + '/' + base)
        return base

    def add_files_to_project(self, *files):
        for f in files:
            b = os.path.basename(f)
            copyfile(f, self.project_dir() + '/' + b)

    def click_dialog(self, role='alert', button='OK'):
        dialog = self.gui.child(roleName=role)
        dialog.grab_focus()
        dialog.child(button).click()

    def launch(self):
        if os.path.exists(self.src_dir()):
            rmtree(self.src_dir())
        copyfile(self.config_file, os.getenv("HOME")
                 + '/.AMC.d/cf.TEST.xml')
        os.environ["LANG"] = "en_US.UTF-8"
        dogtail.utils.run(self.amc_cmd(), timeout=3,
                          appName='auto-multiple-choice')
        self.gui = root.application('AMC-gui.pl')
        self.gui.grab_focus()
        if self.debug:
            self.click_dialog()

    def wait_sensitive(self, node, delay=1, max_delay=30):
        d = 0
        while not node.sensitive and d < max_delay:
            time.sleep(delay)
            d += delay
        if not node.sensitive:
            raise TimeoutError('Waiting for a sensitive button')

    def click_when_sensitive(self, button):
        self.wait_sensitive(button)
        button.click()

    def scroll_and_click(elf, context, value,
                         double=False, enter=False, hold_control=False):
        (base, scrollbar, nbparents) = context
        base.grab_focus()
        y = 0
        ok = False
        print("Click on '%s'" % value)
        x = base.child(value, retry=False)
        disapeared = False
        if x is None:
            raise ValueError(value + ' not found')
        for i in range(nbparents):
            x = x.parent
        while y < 6000 and not ok:
            print("· Scroll to %d" % y)
            scrollbar.value = y
            y += 50
            ok = True
            time.sleep(0.5)
            try:
                if hold_control:
                    registry.generateKeyboardEvent(
                        control_code, None, KEY_PRESS)
                    time.sleep(0.2)
                if double:
                    x.doubleClick()
                else:
                    x.click()
                    if enter:
                        time.sleep(0.2)
                        dogtail.rawinput.pressKey('\n')
                if hold_control:
                    time.sleep(0.2)
                    registry.generateKeyboardEvent(
                        control_code, None, KEY_RELEASE)
                disapeared = len(base.findChildren(
                    dogtail.predicate.GenericPredicate(value))) == 0
            except:
                ok = False
            if not (disapeared or x.selected):
                ok = False
        if ok:
            print("Success!")
            time.sleep(0.5)
        else:
            raise ValueError(value + ' could not be clicked')

    def file_chooser_or_dialog(self):
        found = self.gui.findChildren(
            dogtail.predicate.GenericPredicate(
                roleName='file chooser'))
        if len(found) == 0:
            found = self.gui.findChildren(
                dogtail.predicate.GenericPredicate(
                    roleName='dialog'))
            return(found[0])
        else:
            d = found[0].findAncestor(dogtail.predicate.GenericPredicate(
                roleName='dialog'))
            if d:
                return(d)
            else:
                return(found[0])

    def chooser_locations(self):
        loc_list = self.file_chooser_or_dialog().child(roleName='list box')
        scrollbar = loc_list.parent.parent.findChildren(
            dogtail.predicate.GenericPredicate(roleName='scroll bar'))[1]
        return (loc_list, scrollbar, 4)

    def chooser_files_table(self):
        table = self.file_chooser_or_dialog().child('Files', roleName='table')
        scrollbar = table.parent.findChildren(
            dogtail.predicate.GenericPredicate(roleName='scroll bar'))[1]
        return (table, scrollbar, 1)

    def select_in_current_dir(self, filename,
                              buttonName='Apply',
                              double=False, enter=False,
                              hold_control=False):
        self.scroll_and_click(self.chooser_files_table(),
                              filename,
                              double=double, enter=enter,
                              hold_control=hold_control)
        chooser = self.file_chooser_or_dialog()
        if buttonName != '':
            time.sleep(0.5)
            chooser.child(buttonName).click()
        return chooser

    def select_multiple_in_src_dir(self, files, buttonName='OK'):
        dialog = self.select_in_src_dir(files[0], buttonName='')
        files = files[1:]
        if files:
            for f in files:
                self.select_in_current_dir(f, hold_control=True, buttonName='')
        if buttonName != '':
            dialog.child(buttonName).click()

    def goto_tmp_dir(self):
        self.scroll_and_click(self.chooser_locations(), self.tmp_bookmark)

    def select_in_src_dir(self, filename, buttonName='Apply'):
        self.goto_tmp_dir()
        self.scroll_and_click(self.chooser_files_table(),
                              self.src_dirname, enter=True)
        dialog = self.select_in_current_dir(filename, buttonName=buttonName)
        return dialog

    def tab(self, tabname):
        return self.gui.child(tabname, roleName='page tab')

    def new_project_base(self):
        # First remove project if already existing
        if os.path.isdir(self.project_dir()):
            rmtree(self.project_dir())
        # Go to AMC window and click 'New'
        self.gui.grab_focus()
        self.gui.child('New').click()
        # Choose directory for project
        dialog = self.gui.child('New AMC project')
        dialog.grab_focus()
        directory = dialog.child(roleName='combo box')
        if directory.combovalue != self.tmp_bookmark:
            directory.combovalue = self.tmp_bookmark
        # Choose name for project
        name = dialog.child(roleName="text")
        name.text = self.project_name
        # Process
        dialog.child('New project').click()

    def new_project_mode(self, mode):
        self.gui.child('Source file').grab_focus()
        self.gui.child(mode, roleName='radio button').click()
        self.gui.child('Forward').click()

    def new_project_from_file(self, source_path):
        self.new_project_base()
        # Copy source file in src_dir and select it
        base = self.copy_in_src_dir(source_path)
        self.new_project_mode('File')
        self.select_in_src_dir(base)
        # Alert "File is copied in project directory" -> OK
        self.click_dialog()

    def new_project_from_template(self,
                                  section='[EN] Documentation',
                                  template='Simple example'):
        self.new_project_base()
        self.new_project_mode('Template')
        dialog = self.gui.child('Template selection')
        endoc = dialog.child(section)
        endoc.actions['expand or contract'].do()
        dialog.child(template).click()
        dialog.child('Apply').click()

    def new_project_from_archive(self, archive_path):
        self.new_project_base()
        self.new_project_mode('Archive')
        base = self.copy_in_src_dir(archive_path)
        self.select_in_src_dir(base)

    def new_project_from_text(self, filter="AMC-TXT",
                              text=''):
        self.new_project_base()
        self.new_project_mode('Empty')
        # Set filter
        preparation = self.tab('Preparation')
        f = preparation.child(roleName='combo box')
        if f.combovalue != filter:
            f.combovalue = filter
        preparation.child('Edit source file').click()
        time.sleep(1)
        if os.getenv("DISPLAY") != ":0":
            # with Xvfb and dbus-run-session, gedit faces timeouts so
            # we have to wait a little.
            time.sleep(30)
        gedit = root.application('gedit')
        for t in gedit.findChildren(
                dogtail.predicate.GenericPredicate(roleName='text')):
            if t.text != "":
                print("Set text to:\n" + text)
                t.text = text
        gedit.child('Save').click()
        gedit.child('Save').parent.child('Close').click()

    def build_documents(self):
        self.gui.grab_focus()
        self.click_when_sensitive(self.gui.button('Update documents'))
        self.click_when_sensitive(self.gui.button('Layout detection'))
        time.sleep(2)

    def build_other_document(self, i):
        """Build another document, with index i:
        i=0 leads to th catalog
        i=1 leads to the solution
        i=2 leads to the individual solution"""

        documents = self.tab('Preparation').child('Documents',
                                                  roleName='toggle button')
        documents.click()
        up = sorted([(a.position[1], a)
                     for a in self.gui.findChildren(
            dogtail.predicate.GenericPredicate(
                description='Update the document',
                roleName='panel'))])[i][1]
        up.child(roleName='push button').click()
        time.sleep(2)
        documents.click()

    def print_to_cups(self, copies=[1, 2, 3],
                      printer='CUPS-PDF-Printer'):
        if os.path.exists(self.cups_pdf_dir):
            rmtree(self.cups_pdf_dir)
        os.mkdir(self.cups_pdf_dir)
        self.tab('Preparation').child('Print papers',
                                      roleName='push button').click()
        dialog = self.gui.child(roleName='dialog')
        dialog.grab_focus()
        # select copies
        copies_table = dialog.child(roleName='table')
        for i in copies:
            copies_table.child(str(i)).select()
        # select printer
        cb = dialog.child('Printer:').parent.child(roleName='combo box')
        items = [i.name for i in cb.findChildren(
            dogtail.predicate.GenericPredicate(
                roleName='menu item'))]
        print(items)
        full_printer = ''
        for i in items:
            if printer in i:
                full_printer = i
        print("Printing to %s" % full_printer)
        if cb.combovalue != full_printer:
            cb.combovalue = full_printer
        # - go
        dialog.child('OK').click()
        # few sheets to print -> photocopy mode = No
        self.click_dialog(button="No")
        # return printed files
        printed_files = os.listdir(self.cups_pdf_dir)
        for f in printed_files:
            self.copy_in_src_dir(self.cups_pdf_dir + '/' + f)
        return printed_files

    def print_to_file(self, copies=[1, 2, 3], password=False):
        self.tab('Preparation').child('Print papers',
                                      roleName='push button').click()
        dialog = self.gui.child(roleName='dialog')
        dialog.grab_focus()
        # select copies
        copies_table = dialog.child(roleName='table')
        for i in copies:
            copies_table.child(str(i)).select()
        # - create and select destination directory
        label = dialog.child('Destination directory')
        cb = label.parent.child(roleName='combo box')
        cb.combovalue = 'Other…'
        time.sleep(0.5)
        
        self.goto_tmp_dir()
        self.scroll_and_click(self.chooser_files_table(),
                              self.project_name, double=True)
        chooser = self.file_chooser_or_dialog()
        chooser.child('Create Folder').click()
        create_group = chooser.child('Folder Name').parent
        create_group.child(roleName='text').text = self.print_subdir
        create_group.child('Create').click()
        chooser.child('Open').click()
        # password for pdfforms
        if password:
            pw = dialog.child('Lock with password:')
            pw.click()
            pw.parent.child(roleName='text').text = self.global_password
        # - go
        dialog.child('OK').click()
        # few sheets to print -> photocopy mode = No
        self.click_dialog(button="No")

    def scan_from_blank_copy(self, student=2, dest='scan-blank-2.jpg'):
        os.system("convert -density 300 \"%s/%s/sheet-%04d.pdf\" \"%s/%s\""
                  % (self.project_dir(), self.print_subdir, student,
                     self.src_dir(), dest))

    def scan_from_individual_solution(self, pages=[3], dest='scan-sol-3.pdf'):
        p = " ".join([str(x) for x in pages])
        os.system(("qpdf \"%s/DOC-indiv-solution.pdf\"" +
                   " --pages \"%s/DOC-indiv-solution.pdf\" %s" +
                   " -- \"%s/%s\"") %
                  (self.project_dir(),
                   self.project_dir(), p,
                   self.src_dir(), dest))

    def auto_data_capture(self, files,
                          prealloc=False,
                          mode='Different answer sheets'):
        # Change tab: DATA CAPTURE
        capture = self.tab('Data capture')
        capture.select()
        # Launch automatic data capture
        self.gui.child('Automatic', roleName='push button').click()
        # Choose mode
        choix = self.file_chooser_or_dialog()
        i = choix.menuItem(mode)
        cb = i.parent.parent
        cb.click()
        i.click()
        # pre-allocation
        if prealloc:
            prealloc = [a for a in choix.findChildren(
                dogtail.predicate.GenericPredicate(
                    roleName='check box')) if a.name.startswith('Pre-allocate')][0]
            prealloc.click()
        # choose files
        self.select_multiple_in_src_dir(files, buttonName='OK')
        time.sleep(2)

    def edit_with_zooms(self, page, check=[], uncheck=[], save=True):
        # Change tab: DATA CAPTURE
        capture = self.tab('Data capture')
        capture.select()
        # select line:
        capture.child(page, roleName='table cell').click()
        # open zooms window
        capture.child('Zooms').click()
        dialog = self.gui.child('Zooms', roleName='frame')
        # mode
        mode = dialog.child(roleName='combo box')
        if mode.combovalue != 'click':
            mode.combovalue = 'click'
        # unchecked zone
        zone = dialog.child('Unchecked boxes').parent
        check.sort()
        check.reverse()
        for i in check: 
            unchecked_zooms = sorted([(a.position[1], a.position[0], a)
                                      for a in zone.findChildren(
                                              dogtail.predicate.GenericPredicate(
                                                  roleName='icon'))])
            unchecked_zooms[i-1][2].click()
        # checked zone
        uncheck.sort()
        uncheck.reverse()
        for i in uncheck:
            zone = dialog.child('Checked boxes').parent
            checked_zooms = sorted([(a.position[1], a.position[0], a)
                                    for a in zone.findChildren(
                                            dogtail.predicate.GenericPredicate(
                                                roleName='icon'))])
            checked_zooms[i-1][2].click()
        # save and exit
        if save:
            dialog.child('Save').click()
        dialog.child('Close').click()
        if not save:
            self.click_dialog(button="Yes")

    def goto_manual_data_capture(self, page):
        # Change tab: DATA CAPTURE
        capture = self.tab('Data capture')
        capture.select()
        # Open manual data capture window
        capture.child('Manual').click()
        # click on line
        dialog = self.gui.child('Paper data capture', roleName='frame')
        dialog.child(page, roleName='table cell').click()
        return dialog

    def cancel_manual_data_capture(self, page):
        dialog = self.goto_manual_data_capture(page)
        dialog.child('Delete').click()
        dialog.child('Quit').click()

    def sql_row(self, query, base='layout', numeric=False):
        db = self.project_dir() + '/data/' + base + '.sqlite'
        row = subprocess.check_output(['sqlite3', '-line', db, query]).split(b'\n')
        q = {}
        for line in row:
            v=line.decode('utf8').split()
            if len(v) == 3:
                if numeric:
                    q[v[0]] = float(v[2])
                else:
                    q[v[0]] = v[2]
        return q

    def box_pos(self, student, question, answer):
        return self.sql_row("select * from layout_box where role=1 and student=%d and question=%d and answer=%d;" % (student, question, answer), numeric=True)

    def page_size(self, student, page):
        return self.sql_row("select * from layout_page where student=%d and page=%d;" % (student, page), numeric=True)

    def manual_data_capture(self, page, student, clicks=[]):
        """Opens the manual data capture window, select page <page>,
        and click on boxes (question, answer) in array <clicks>."""
        
        dialog = self.goto_manual_data_capture(page)
        draw = dialog.child(roleName='drawing area')
        for (q,a) in clicks:
            box = self.box_pos(student, q, a)
            print(box)
            page = self.page_size(student, int(box["page"]))
            xx = (box["xmin"]+box["xmax"])/2
            yy = (box["ymin"]+box["ymax"])/2
            x = draw.position[0] + xx * draw.size[0]/page["width"]
            y = draw.position[1] + yy * draw.size[0]/page["width"]
            dogtail.rawinput.point(x,y)
            time.sleep(0.2)
            dogtail.rawinput.click(x,y)
            time.sleep(0.2)
        dialog.child('Quit').click()

    def mark(self):
        marking = self.tab('Marking')
        marking.select()
        time.sleep(1)
        marking.child('Mark', roleName='push button').click()
        time.sleep(3)

    def postcorrect(self, student, copy=0):
        dialog = self.gui.child('Post-correction')
        spin = sorted([(a.position[0], a)
                       for a in dialog.findChildren(
                               dogtail.predicate.GenericPredicate(
                                   roleName='spin button'))])
        spin[0][1].value = student
        spin[1][1].value = copy
        dialog.child('Apply').click()

    def set_students_list(self, students_file, auto=True,
                          uid='id', code='Pre-association'):
        marking = self.tab('Marking')
        marking.select()
        marking.child('Set file', roleName='push button').click()
        self.select_in_current_dir(students_file)
        # select uid/code for association
        cbs = sorted([(a.position[1], a)
                      for a in marking.findChildren(
            dogtail.predicate.GenericPredicate(
                roleName='combo box'))])
        cbs[0][1].combovalue = uid
        if auto:
            cbs[1][1].combovalue = code
            # go for automatic association
            marking.child('Automatic', roleName='push button').click()
            # validate result
            self.click_dialog()

    def manual_association(self, sequence=[]):
        marking = self.tab('Marking')
        marking.select()
        marking.child('Manual', roleName='push button').click()
        dialog = self.gui.child('Manual association')
        for n in sequence:
            time.sleep(0.5)
            dialog.child(n).click()
        time.sleep(0.5)
        dialog.child('Quit').click()

    def report(self, output_format='OpenOffice', options_cb=[]):
        """Build the report, where output_format can be 'OpenOffice',
        'CSV', 'PDF list' (or other if plugins are installed)."""

        reports = self.gui.child('Reports', roleName='page tab')
        reports.select()
        export_button = reports.child('Export', roleName='push button')
        export_bar = export_button.parent
        cbx = sorted([(a.position[0], a)
                      for a in export_bar.findChildren(
            dogtail.predicate.GenericPredicate(
                roleName='combo box'))])
        reports.grab_focus()
        if output_format:
            if cbx[0][1].combovalue != output_format:
                cbx[0][1].combovalue = output_format
        if cbx[1][1].combovalue != 'that\'s all':
            cbx[1][1].combovalue = 'that\'s all'
        # options: find option group for output_format…
        if output_format:
            if output_format == 'OpenOffice':
                options = reports.child('Stats table').parent
            if output_format == 'CSV':
                options = reports.child('Ticked boxes').parent
            if output_format == 'PDF list':
                options = reports.child('Paper size').parent
            cbx = sorted([(a.position[1], a)
                          for a in options.findChildren(
                                  dogtail.predicate.GenericPredicate(
                                      roleName='combo box'))])
            for o in options_cb:
                if cbx[o[0]][1].combovalue != o[1]:
                    cbx[o[0]][1].combovalue = o[1]
        # go
        export_button.click()

    def check_csv_results(self, checks):
        errors = 0
        with open(self.project_dir() + "/exports/" +
                  self.code() + '.csv') as csv_file:
            csv_reader = csv.DictReader(csv_file, delimiter=';')
            for row in csv_reader:
                e = row["Exam"]
                if e in checks:
                    for k, v in checks[e].items():
                        if row[k] == v:
                            print("CSV[%s]: %s = %s"
                                  % (e, k, v))
                        else:
                            print("CSV[%s]: %s is %s instead of %s"
                                  % (e, k, row[k], v))
                            errors += 1
                    checks[e]["_done"] = True
        if errors > 0:
            raise ValueError("Exported CSV is not valid.")
        missing = [k for k in checks if not checks[k].get("_done", False)]
        if len(missing) > 0:
            raise ValueError("Missing CSV line for "+", ".join(missing))

    def check_annotated_files_exist(self, *files):
        errors = 0
        for f in files:
            if os.path.isfile(self.project_dir()
                              + '/cr/corrections/pdf/' + f):
                print("[Annotated] OK %s" % f)
            else:
                print("[Annotated] MISSING %s" % f)
                errors += 1
        if errors > 0:
            raise ValueError("Some annotated answer sheets are missing.")

    def annotate(self, model='(id)_(ID)'):
        reports = self.gui.child('Reports', roleName='page tab')
        reports.select()
        annotated = reports.child('Annotated papers', roleName='panel')
        annotated.child(roleName='text').text = model
        reports.child('Annotate papers', roleName='push button').click()

    def set_options(self,
                    description=['TEST EXAM', 'test'],
                    printing_method = None):
        self.gui.child('Properties', roleName='push button').click()
        dialog = self.gui.child('AMC Preferences')
        dialog.grab_focus()
        tab = dialog.child('Main', roleName='page tab')
        if printing_method:
            time.sleep(1)
            # scroll to tab bottom
            sb = tab.findChildren(
                dogtail.predicate.GenericPredicate(roleName='scroll bar'))
            sb[1].value =2000
            # Find printing method combo box 
            desc = dialog.child('Printing')
            ts = sorted([(a.position[1], a)
                         for a in desc.findChildren(
                                 dogtail.predicate.GenericPredicate(
                                     roleName='combo box'))])
            if ts[0][1].combovalue != printing_method:
                ts[0][1].combovalue = printing_method
        dialog.child('Project', roleName='page tab').select()
        if description:
            time.sleep(1)
            desc = dialog.child('Examination description')
            ts = sorted([(a.position[1], a)
                         for a in desc.findChildren(
                dogtail.predicate.GenericPredicate(
                    roleName='text'))])
            ts[0][1].text = description[0]
            ts[1][1].text = description[1]
            self.shortcode = description[1]
        time.sleep(2)
        dialog.child('OK').click()
        time.sleep(2)

    def finished(self):
        self.gui.child('Close').click()
        print("")
        print("********************")
        print("*     SUCCESS!     *")
        print("********************")
