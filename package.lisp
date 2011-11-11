;; Copyright (C) 2011  Eric Schulte
(defpackage #:soft-ev
  (:use
   :common-lisp
   :alexandria
   :split-sequence
   :metabang-bind
   :cl-store
   :trivial-shell
   :cl-ppcre)
  (:shadow :type)
  (:export
   ;; functions
   :evolve
   ;; slots
   ;; methods
   ;; constants and variables
   :*population*
   :*max-population-size*
   :*tournament-size*
   :*fitness-predicate*
   :*test-script*
   :*pos-test-num*
   :*neg-test-num*
   :*pos-test-mult*
   :*neg-test-mult*
   :*keep-source*
   :*cross-chance*
   :*fitness-evals*
   ))
