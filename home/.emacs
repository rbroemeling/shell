; Enable font-lock mode.
(require 'font-lock)
(global-font-lock-mode t)

; Scroll one line at a time instead of jumping around.
(setq scroll-step 1)

; Always end a file with a newline (instead of nothing).
(setq require-final-newline t)

; Prompt for 'y' or 'n' instead of 'yes' or 'no'.
(fset 'yes-or-no-p 'y-or-n-p)

; Display column number in toolbar.
(column-number-mode t)

; Highlight the marked region.
(transient-mark-mode t)

; Enable parenthesis matching.
(show-paren-mode 1)

; Force the time displayed in the toolbar to use a 24hr clock.
(setq display-time-24hr-format t)

; Force the date to be displayed along with the time in the toolbar.
(setq display-time-day-and-date t)

; Enable display of time in the toolbar.
(display-time)

; Enable use of a visual bell instead of an audible one.
(setq visible-bell t)

; Disable scrollbars.
(and (fboundp 'scroll-bar-mode) (scroll-bar-mode nil))

; Disable menu bar.
(and (fboundp 'menu-bar-mode) (menu-bar-mode nil))

; Disable tool bar.
(and (fboundp 'tool-bar-mode) (tool-bar-mode nil))

; Disable the welcome message.
(setq inhibit-startup-message t)

; Disable auto-saving of files.
(setq auto-save-default nil)

; Set the directory that emacs will put all of it's backup (*~) files in.
(if (not (file-exists-p "~/.emacs.d/backups")) (make-directory "~/.emacs.d/backups" t))
(setq backup-directory-alist '(("." . "~/.emacs.d/backups")))

; Configure emacs backups to keep a number of past revisions in case they are
; ever needed, but to delete backups past the threshold without prompting.
(setq delete-old-versions t
	kept-new-versions 6
	kept-old-versions 2
	version-control t)

; Configure emacs to create backups by copying the original file (safest
; option available).
(setq backup-by-copying t)

; Disable auto-wrapping of long lines: instead, have emacs truncate them
; to fit them on the screen.
(setq default-truncate-lines t)

; Turn off the use of tabs rather than spaces for indentation.
(setq indent-tabs-mode nil)
(setq-default indent-tabs-mode nil)

; Bind the TAB key to insert a tab.
(global-set-key (kbd "TAB") 'self-insert-command)

; Configure TAB widths.
(setq default-tab-width 2)
(setq tab-width 2)
(setq c-basic-indent 2)

; Configure PERL TAB widths.
(setq perl-indent-level 2)
(setq perl-continued-statement-offset 2)
