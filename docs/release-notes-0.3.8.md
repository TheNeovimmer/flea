# Flea 0.3.8

- Copy, cut and paste reach the system clipboard, so they work between two Flea windows and with other file managers (#203, @akitaonrails).
- A drag between windows moves within a drive, copies across drives, and says the verb it will perform; a drop from another app follows that app's action (#212, @shawnyeager).
- Drop modifiers held at lift: Shift moves, Ctrl copies, Ctrl+Shift links.
- Trackpad scrolling matches Finder's speed, coasts after the fingers lift, and stretches at a list's ends; the mouse wheel is unchanged.
- [ and ] switch tabs, and tabs move by key or by drag (#163, @muellan).
- A middle click on a folder opens it in a new tab, and Ctrl+Return does the same for the folder under the cursor (#219, @matt-shearing; #229, @alextakitani).
- F5 and Ctrl+R reload the folder and say how many rows changed (#197, @johnkattenhorn; #80, @avillagran).
- A slow second click renames, a single click can open, and the list keeps context rows around the cursor.
- Escape can go up a folder, off by default (#29, @herr-brandt).
- Copy as copies the path, name or URI of the whole selection, and Ctrl+Shift+C copies its paths (#189, @AksharP5; #188, @AksharP5).
- Invert selection on V (#164, @muellan).
- Permissions takes several rows at once and shows mixed values (#220, @muellan).
- Paste as links and Show original in the menus.
- Make executable for a script with a shebang, and Open in terminal from the background menu.
- Recent in the sidebar, off by default, and favourites reorder by drag (#99, @morgoth).
- The keymap sheet finds menu rows, places and recent files, and ? opens it in Trash too (#227, @bcosta19; #228, @bcosta19).
- Kind sort breaks ties by extension (#190, @markallisongit).
- A Shift range keeps the rows already marked (#209, @muellan).
- Rename starts on the first try (#170, @MISTERNEGATIVE21).
- Return and keypad Enter confirm the file picker under the Mac preset (#225, @pomartel; #240, @GreyforgeLabs).
- The file picker gains a grid view with thumbnails and remembers the view last used (#191, @dyedfox).
- Markdown renders in Quick Look and the preview column, with Source one key away (#204, @fsrodrig).
- Markdown draws aligned tables (one too wide for its pane scrolls sideways and never splits a word), task lists, footnotes, nested lists and quotes, math and Mermaid diagrams, and the HTML a README uses: centred headers, pictures and badge rows, details, kbd, sub and sup.
- Previews appear about ten times sooner on a single move, and Quick Look shows the cached thumbnail while the full image decodes.
- The mouse forward button retraces a back, and does nothing while Trash is open (#236, @t1nk333r).
- Columns view's side columns follow files created, renamed or deleted by other programs (#244, @muellan).
- Every open tab can come back with Last folder.
- A revealed auto-hide sidebar takes its click, and a click-away rename commit keeps the clicked row.
- A key pressed right after clicking a selected name runs alone, with no rename editor opening behind it.
- Menus and flyouts widen to their widest row, so a long label is no longer cut beside its key hint (#213, @AksharP5).
- Menus, flyouts and the sidebar draw no scrollbar and keep no room for one; in a menu the wheel and trackpad move the highlight.
- A hung NFS, SMB or other network share no longer freezes Flea: listings, previews and file operations on it answer within seconds, and a slow rename or new folder says it is still running and finishes on its own.
- Moving 1,000 small files to a USB stick confirms every file on the stick before its source is removed, in about 4.3 s against 6.6 s for 0.3.7 measured the same way on the same stick (medians of 18 runs each; the 9.62 s in 0.3.7's notes came from a different harness).
- Undo and redo stay quick after a long session: one operation reads and writes the shared undo history once.
- Partitions with no filesystem, and EFI and other system partitions, no longer appear in the sidebar (#232, @MiguelDebruyne).
- A folder rename on an NFS server that refuses no-replace renames works in place (#245, @akitaonrails).
- Kernel NFS and CIFS mounts, and FUSE mounts outside home, appear with the network places.
- Tested on ext4, btrfs, xfs, f2fs, exfat, vfat, NTFS and NFS: renaming to a different case works on FAT, exFAT and NTFS, a copy over 4 GiB to FAT refuses before writing, mount and permission errors say why, and the status bar names every filesystem.
- One button style everywhere: every dialog, strip and card button draws the same frame, hover, press and focus ring.
- A focused field draws its own frame in the theme accent, and so does a focused protocol chip in the Network dialog.
- Rename uses the list view's editor in every view.
- The terminal version's rename editor no longer paints terminal control characters from a file name (#239, @GreyforgeLabs).
- flea-git now updates on every release with flea and flea-bin.
- The test suites run headless on an Omarchy box with no display, on Qt's generic theme (#253, @nixfred).

Known issues

- A new window maps about 35 ms later than 0.3.7 on a local folder and about 50 ms later on a USB folder, so PCManFM's window appears first on both (532 and 550 ms against 464 and 524, medians of 5 runs); the startup cost is the first item for 0.3.9.
- USB folders rank fourth for GUI PSS among the file managers measured (third in 0.3.7; 88.9 MB against 86.4 MB for 0.3.7 in the same run) and NAS folders third; PCManFM skips thumbnails on removable and network media, and Flea's floor is the Quickshell and Qt base.
- On the NAS, Strata settles with slightly less CPU (1.38 s against 1.44 s), as in 0.3.7.
- Quick Look's first Space on a Markdown document whose first screen is a table draws about 37 ms later than other documents (60 ms against about 23 ms), still ahead of Strata's 104 ms.
- The 5 GB memory growth and crash in #151 have not been reproduced; the report stays open.
- The NFS problem reported on 0.3.5 remains unexplained.
- The memory and CPU items deferred from 0.3.7 (List view memory, USB anonymous memory, the NAS backend's executable PSS, the driven navigation CPU cost and a 2-3 ms cached image-folder revisit) were not measured again for this release and move to 0.3.9.

Thanks to @akitaonrails, @shawnyeager, @muellan, @matt-shearing, @alextakitani, @johnkattenhorn, @avillagran, @herr-brandt, @AksharP5, @morgoth, @bcosta19, @markallisongit, @MISTERNEGATIVE21, @pomartel, @GreyforgeLabs, @dyedfox, @fsrodrig, @t1nk333r, @MiguelDebruyne and @nixfred.

Source revision: 6668e4f4756ad77a0914100fbd7a5b9058025c6c (v0.3.8).
