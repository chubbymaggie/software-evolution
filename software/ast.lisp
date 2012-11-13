;;; ast.lisp --- ast software representation

;; Copyright (C) 2012  Eric Schulte

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; TODO: get memoization working

;;; Code:
(in-package :software-evolution)


;;; ast software objects
(defclass ast (software)
  ((base    :initarg :base    :accessor base    :initform nil)
   (c-flags :initarg :c-flags :accessor c-flags :initform nil)))

(defmethod copy ((ast ast))
  (make-instance (type-of ast)
    :c-flags (copy-tree (c-flags ast))
    :base    (base ast)
    :fitness (fitness ast)
    :edits   (copy-tree (edits ast))))

(defun ast-from-file (path &key c-flags)
  (assert (listp c-flags) (c-flags) "c-flags must be a list")
  (make-instance 'ast
    :base    (file-to-string path)
    :c-flags c-flags))

(defun ast-to-file (software path &key if-exists)
  (string-to-file (genome software) path :if-exists if-exists))

(defun genome-helper (ast)
  (if (edits ast)
      (let ((parent (copy ast)))
        (pop (edits parent))
        (ast-mutate (genome-helper parent) (car edits)))
      base))
;; (memoize-function 'genome-helper :key #'identity)
;; (unmemoize-function 'genome-helper)

(defmethod genome ((ast ast)) (genome-helper ast))

(defgeneric ast-mutate ((ast ast) op)
  (:documentation "Mutate AST with either clang-mutate or cil-mutate."))

(defun num-ids (ast)
  (handler-case
      (read-from-string
       (ast-mutate ast (list :ids)))
    (ast-mutate (err) (declare (ignorable err)) (format t "caught") 0)))

(defmethod mutate ((ast ast))
  "Randomly mutate VARIANT with chance MUT-P."
  (let ((num-ids (num-ids ast)))
    (unless (and num-ids (> num-ids 0)) (error 'mutate "No valid IDs"))
    (setf (fitness ast) nil)
    (flet ((place () (random num-ids)))
      (push (case (random-elt '(cut insert swap))
              (cut    `(:cut    ,(place)))
              (insert `(:insert ,(place) ,(place)))
              (swap   `(:swap   ,(place) ,(place))))
            (edits ast)))
    ast))

(defmethod patch-subset ((a ast) (b ast))
  "Return a new ast composed of subsets of the edits from A and B."
  (let ((new (copy a)))
    (flet ((some-of (edits)
             (remove-if (lambda (_) (declare (ignorable _)) (zerop (random 2)))
                        (butlast edits 1))))
      (setf (edits new)
            (append (some-of (edits a)) (some-of (edits b))
                    (last (edits a))))
      (setf (fitness new) nil)
      new)))

(defmethod crossover ((a ast) (b ast)) (patch-subset a b))