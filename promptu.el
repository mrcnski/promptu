;;; promptu.el --- Compose LLM prompts from building blocks -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author: Marcin Swieczkowski
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (transient "0.3.0"))
;; Keywords: convenience, tools
;; URL: https://github.com/mrcnski/promptu

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; promptu provides a transient menu that composes an LLM prompt from
;; user-customizable building blocks, copying the result to the kill ring.
;;
;; The opposite of impromptu: composed, not off-the-cuff.
;;
;; Usage:
;;   M-x promptu
;;
;; Pick blocks one at a time; the menu stays open and shows a live preview
;; as blocks accumulate.  Blocks can prompt for runtime values and can be
;; negated.  Press RET to copy the composed prompt to the kill ring, or q
;; (or C-g) to abort.
;;
;; Keys inside the menu:
;;   <block keys>  add that block
;;   -             arm "negate next" (the next block added is negated)
;;   DEL           remove the most recently added block
;;   RET           finish: copy the composed prompt to the kill ring
;;   q / C-g       abort with no output
;;
;; See `promptu-blocks' to customize the available blocks.

;;; Code:

(require 'transient)
(require 'subr-x)

(defgroup promptu nil
  "Compose LLM prompts from building blocks."
  :group 'convenience
  :prefix "promptu-")

(defcustom promptu-blocks
  '((:key "r" :desc "review"        :text "review your changes")
    (:key "c" :desc "commit"        :text "commit")
    (:key "t" :desc "add tests"     :text "add tests" :negative "skip the tests")
    (:key "p" :desc "push"          :text "push when done")
    (:key "k" :desc "check CI"      :text "check CI")
    (:key "b" :desc "create branch" :text "create a branch")
    (:key "i" :desc "investigate"   :text "investigate {link}" :placeholders ("link")))
  "Building blocks available in the `promptu' menu.

Each block is a plist with these keys:

  :key          string, the transient trigger key (must avoid the
                reserved keys -, RET, DEL, q).
  :desc         string, the short menu description.
  :text         string, the affirmative text emitted into the prompt.
                May contain named placeholders written as {name}.
  :negative     optional string, the text emitted when the block is
                negated.  When absent, a negated block emits :text
                prefixed with `promptu-negation-prefix'.
  :placeholders optional list of placeholder names (strings).  When
                present, the user is prompted in the minibuffer for each
                value, which is substituted for the matching {name} in
                :text before the block joins the prompt."
  :type '(repeat
          (plist :options ((:key string)
                           (:desc string)
                           (:text string)
                           (:negative string)
                           (:placeholders (repeat string)))))
  :group 'promptu)

(defcustom promptu-separator "\n- "
  "Separator placed between blocks in the composed prompt.

When the separator contains a newline, the text following its last
newline is also prepended to the first block as a line prefix, so the
default \"\\n- \" produces a fully bulleted list."
  :type 'string
  :group 'promptu)

(defcustom promptu-negation-prefix "don't "
  "Prefix prepended to a negated block's affirmative text.

Used only when a negated block does not define explicit :negative text."
  :type 'string
  :group 'promptu)

;;; Pure compose core

(defun promptu--substitute (text values)
  "Substitute placeholders in TEXT using VALUES.
VALUES is an alist of (NAME . VALUE) where NAME is a placeholder name
string; each occurrence of {NAME} in TEXT is replaced with VALUE."
  (let ((result text))
    (dolist (pair values result)
      (setq result (string-replace (format "{%s}" (car pair)) (cdr pair) result)))))

(defun promptu--resolve (block affirmative negated)
  "Return the text BLOCK emits given its substituted AFFIRMATIVE text.
When NEGATED is non-nil, emit BLOCK's :negative text if defined, else
AFFIRMATIVE prefixed with `promptu-negation-prefix'.  When NEGATED is
nil, emit AFFIRMATIVE unchanged."
  (if negated
      (or (plist-get block :negative)
          (concat promptu-negation-prefix affirmative))
    affirmative))

(defun promptu--line-prefix (separator)
  "Return the text following the last newline in SEPARATOR, or \"\" if none."
  (if (string-match "\n\\([^\n]*\\)\\'" separator)
      (match-string 1 separator)
    ""))

(defun promptu--compose (entries)
  "Join ENTRIES (a list of resolved strings) into the composed prompt.
Entries are joined with `promptu-separator'; when the separator contains
a newline, its trailing line prefix is also applied to the first entry."
  (if (null entries)
      ""
    (concat (promptu--line-prefix promptu-separator)
            (string-join entries promptu-separator))))

;;; Session state

(defvar promptu--session nil
  "Ordered list of resolved block strings for the current compose session.
Oldest first; the most recently added block is last.")

(defvar promptu--negate-next nil
  "When non-nil, the next block added is negated, then this resets to nil.")

(defun promptu--reset ()
  "Clear the compose session and the negate-next flag."
  (setq promptu--session nil
        promptu--negate-next nil))

(defun promptu--add (block)
  "Resolve BLOCK and append its text to the session.
Prompts the minibuffer for any :placeholders, substitutes them, applies
negation when `promptu--negate-next' is armed, then resets that flag."
  (let* ((placeholders (plist-get block :placeholders))
         (values (mapcar (lambda (name)
                           (cons name (read-string (format "%s: " name))))
                         placeholders))
         (affirmative (promptu--substitute (plist-get block :text) values))
         (resolved (promptu--resolve block affirmative promptu--negate-next)))
    (setq promptu--session (append promptu--session (list resolved))
          promptu--negate-next nil)))

(defun promptu--remove-last ()
  "Remove the most recently added block from the session.
Safe no-op when the session is empty."
  (interactive)
  (when promptu--session
    (setq promptu--session (butlast promptu--session))))

(defun promptu--toggle-negate ()
  "Toggle the negate-next flag."
  (interactive)
  (setq promptu--negate-next (not promptu--negate-next)))

;;; Finalize and abort

(defun promptu--finish ()
  "Copy the composed prompt to the kill ring and report.
A no-op (no kill-ring change) when the session is empty."
  (interactive)
  (if (null promptu--session)
      (message "promptu: nothing to copy")
    (let ((text (promptu--compose promptu--session))
          (n (length promptu--session)))
      (kill-new text)
      (message "promptu: copied %d block%s to kill ring" n (if (= n 1) "" "s")))))

;;; Transient menu

(defconst promptu--reserved-keys '("-" "RET" "DEL" "q")
  "Keys reserved for menu control; block keys must avoid these.")

(defun promptu--reserved-key-p (key)
  "Return non-nil when KEY is a reserved control key."
  (and (member key promptu--reserved-keys) t))

(defun promptu--make-add-command (block)
  "Return an interactive command that adds BLOCK to the session."
  (lambda ()
    (interactive)
    (promptu--add block)))

(defun promptu--block-suffixes (_)
  "Build transient suffixes from `promptu-blocks'.
One stay-open suffix per block; blocks whose key collides with a reserved
key are skipped with a warning."
  (transient-parse-suffixes
   'promptu
   (let (specs)
     (dolist (block promptu-blocks)
       (let ((key (plist-get block :key)))
         (if (promptu--reserved-key-p key)
             (warn "promptu: block key %S collides with a reserved key; skipping" key)
           (push (list key
                       (plist-get block :desc)
                       (promptu--make-add-command block)
                       :transient t)
                 specs))))
     (nreverse specs))))

(defun promptu--preview ()
  "Render the live preview heading for the menu."
  (concat
   (when promptu--negate-next
     (propertize "negate next: ON\n" 'face 'warning))
   (if promptu--session
       (promptu--compose promptu--session)
     "(empty -- pick blocks below)")))

;;;###autoload
(transient-define-prefix promptu ()
  "Compose an LLM prompt from building blocks."
  [:description promptu--preview
   :class transient-column
   :setup-children promptu--block-suffixes]
  ["Controls"
   ("-"   "negate next"   promptu--toggle-negate :transient t)
   ("DEL" "remove last"   promptu--remove-last   :transient t)
   ("RET" "finish (copy)" promptu--finish)
   ("q"   "abort"         transient-quit-one)]
  (interactive)
  (promptu--reset)
  (transient-setup 'promptu))

(provide 'promptu)

;;; promptu.el ends here
