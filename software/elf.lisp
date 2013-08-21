;;; elf.lisp --- software representation of ELF files

;; Copyright (C) 2011-2013  Eric Schulte

;; Licensed under the Gnu Public License Version 3 or later

;;; Commentary:

;;; Code:
(in-package :software-evolution)


;;; elf software objects
(defclass elf-sw (software)
  ((base      :initarg :base      :accessor base      :initform nil)
   (genome    :initarg :genome    :accessor genome    :initform nil)
   (addresses :initarg :addresses :accessor addresses :initform nil)))

(defvar x86-nop #x90)

(defmethod copy ((elf elf-sw))
  (make-instance (type-of elf)
    :fitness (fitness elf)
    :genome (copy-tree (genome elf))
    :base (base elf))) ;; <- let elf objects *share* an elf object

(defmethod elf ((elf elf-sw))
  "Return the elf object associated with ELF.
This takes the `base' of ELF (which should not be changed), copies it,
and applies the changed data in `genome' of ELF."
  (let ((new (copy-elf (base elf))))
    (setf (data (named-section new ".text"))
          (coerce (mapcan [#'cdr {assoc :bytes}] (copy-tree (genome elf)))
                  'vector))
    new))

(defmethod from-file ((elf elf-sw) path)
  (setf (base elf) (read-elf path))
  (let* ((text (named-section (base elf) ".text"))
         (objdump (objdump-parse (objdump text))))
    (setf (genome elf) (mapcar [#'list {cons :bytes}]
                               (by-instruction text objdump)))
    (setf (addresses elf) (mapcar #'car (mapcan #'cdr (copy-tree objdump)))))
  elf)

(defmethod phenome ((elf elf-sw) &key (bin (temp-file-name)))
  (write-elf (elf elf) bin)
  (shell "chmod +x ~a" bin)
  bin)

(defmethod pick-good ((elf elf-sw)) (random (length (genome elf))))
(defmethod pick-bad ((elf elf-sw)) (random (length (genome elf))))

(defmethod mutate ((elf elf-sw))
  "Randomly mutate ELF."
  (setf (fitness elf) nil)
  (let ((op (case (random-elt '(cut insert swap #|d-cut d-insert d-swap|#))
              (cut      `(:cut    ,(pick-bad elf)))
              (insert   `(:insert ,(pick-bad elf) ,(pick-good elf)))
              (swap     `(:swap   ,(pick-bad elf) ,(pick-good elf)))
              ;; (d-cut    `(:data-cut    ,(d-place)))
              ;; (d-insert `(:data-insert ,(d-place) ,(d-place)))
              ;; (d-swap   `(:data-swap   ,(d-place) ,(d-place)))
              )))
    (apply-mutation elf op)
    (values elf op)))

(defmethod apply-mutation ((elf elf-sw) mut)
  (flet ((byte-count (genome)
           (reduce #'+ (mapcar [#'length {aget :bytes}] genome))))
    (let ((starting-bytes (byte-count (genome elf))))
      (setf (genome elf)
            (case (car mut)
              (:cut    (elf-cut (genome elf) (second mut)))
              (:insert (elf-insert (genome elf) (second mut)
                                   (nth (third mut) (genome elf))))
              (:swap   (elf-swap (genome elf) (second mut) (third mut)))))
      (assert (= (byte-count (genome elf)) starting-bytes)
              (elf) "mutation ~S changed size of genome [~S -> ~S]"
              mut starting-bytes (byte-count (genome elf))))))

(defun elf-cut (genome s1)
  (let ((prev (copy-tree (nth s1 genome)))
        num-bytes)
    (assert (assoc :bytes prev) (prev)
            "attempt to cut genome element with no bytes: ~S" prev)
    (setf num-bytes (length (aget :bytes prev)))
    (setf (cdr (assoc :bytes prev)) (list x86-nop))
    (append (subseq genome 0 s1)
            (loop :for i :below num-bytes :collect prev)
            (subseq genome (1+ s1)))))

(defun elf-insert (genome s1 val)
  (assert (assoc :bytes val) (val)
          "attempt to insert genome element with no bytes: ~S" val)
  (let ((left (length (cdr (assoc :bytes val))))
        (length (length genome)))
    (setf genome (append (subseq genome 0 s1) (list val) (subseq genome s1)))
    (flet ((nop-p (n genome)
             (tree-equal (list x86-nop) (aget :bytes (nth n genome))))
           (del (n)
             (decf left) (decf length)
             (setf genome (delete-if (constantly t) genome :start n :count 1))))
      ;; bookkeeping
      (loop :for i :upto (max s1 (- (length genome) s1)) :while (> left 0) :do
         (let ((f  (+ s1 i)) (b (- s1 i)))
           (loop :while (and (> left 0) (< f length) (nop-p f genome))
              :do (del f))
           (loop :while (and (> left 0) (> b 0) (nop-p b genome))
              :do (del b))))
      genome)))

(defun elf-swap (genome s1 s2)
  (assert (every {assoc :bytes} (mapcar {nth _ genome} (list s1 s2)))
          (s1 s2)
          "attempt to swap genome elements w/o bytes: ~S"
          (cons s1 s2))
  (let ((larger (max s1 s2))
        (smaller (min s1 s2)))
    ;; drop in a place holder marking what we want to change
    (push (list :s1) (nth larger genome))
    (push (list :s2) (nth smaller genome))
    (mapcar (lambda-bind ((point . value))
              ;; adjust to placeholder if necessary
              (let ((point (position-if {assoc point} genome)))
                (setf genome (elf-cut genome point))
                (setf genome (elf-insert genome point value))))
            (sort (mapcar #'cons
                          (list :s1 :s2)
                          (mapcar [#'copy-tree {nth _ genome}] (list s2 s1)))
                  #'< :key [#'length #'cdr]))
    ;; clean out our placeholder
    (setf (nth larger genome)
          (remove :swap-placeholder (nth larger genome) :key #'car))
    genome))

(defmethod crossover ((a elf-sw) (b elf-sw))
  "One point crossover."
  (flet ((borders (elf)
           (let ((counter 0))
             (cdr (reverse (reduce (lambda (ac el) (cons (cons (+ el (caar ac))
                                                          (incf counter))
                                                    ac))
                                   (mapcar #'length (genome elf))
                                   :initial-value '((0))))))))
    (let ((point (random-elt (mapcar #'cdr (intersection (borders a) (borders b)
                                                         :key #'car))))
          (new (copy a)))
      (setf (genome new) (append (subseq (genome a) 0 point)
                                 (subseq (genome b) point)))
      new)))

(defun by-instruction (section &optional objdump)
  (let* ((objdump (or objdump (objdump-parse (objdump section))))
         (data (data section))
         (offsets (mapcar [{- _ (address (sh section))} #'car]
                          (mapcan #'cdr objdump))))
    (mapcar (lambda (start end) (coerce (subseq data start end) 'list))
            offsets
            (append (cdr offsets) (list nil)))))

(defmethod apply-path ((elf elf-sw) key addresses &aux applied)
  (loop :for el :in addresses :as i :from 0 :do
     (let* ((addr  (if (consp el) (car el) el))
            (val   (if (consp el) (cdr el) t))
            (place (position addr (addresses elf))))
       (when place
         (push (cons key val) (nth place (genome elf)))
         (push (list i key val) applied))))
  (reverse applied))
