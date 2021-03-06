;;
;;  cl-stream  -  Stream class for Common Lisp
;;
;;  Copyright 2017 Thomas de Grivel <thoxdg@gmail.com>
;;
;;  Permission to use, copy, modify, and distribute this software for any
;;  purpose with or without fee is hereby granted, provided that the above
;;  copyright notice and this permission notice appear in all copies.
;;
;;  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
;;  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
;;  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
;;  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
;;  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
;;  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
;;  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
;;

(in-package :cl-stream)

(defclass stream ()
  ((open-p :initform t
           :accessor stream-open-p
           :type boolean))
  (:documentation "Base class for all streams."))

(defgeneric stream-element-type (stream)
  (:documentation "Returns the type of elements of STREAM."))

(defgeneric stream-blocking-p (stream)
  (:documentation "Returns T if STREAM is in blocking mode,
or NIL if in non-blocking mode."))

(defgeneric (setf stream-blocking-p) (value stream)
  (:documentation "Set to T to put STREAM in blocking mode,
or NIL for non-blocking mode."))

(defmethod stream-blocking-p ((stream stream))
  t)

(define-condition stream-error (error)
  ((stream :initarg :stream
           :reader stream-error-stream
           :type stream))
    (:documentation "Superclass for all errors related to streams."))

(define-condition stream-closed-error (stream-error)
  ()
  (:report (lambda (condition stream)
             (format stream "~S is closed."
                     (stream-error-stream condition))))
  (:documentation "An error that is signalled when trying to read from
or write to a closed stream."))

(define-condition stream-end-error (stream-error)
  ()
  (:report (lambda (condition stream)
             (format stream "End of stream ~S."
                     (stream-error-stream condition))))
  (:documentation "An error that is signalled when stream end was reached."))

(defgeneric check-if-open (stream))

(defmethod check-if-open ((stream stream))
  "Checks if STREAM is open and signals an error otherwise."
  (unless (stream-open-p stream)
    (error 'stream-closed-error
           :stream stream)))

(defgeneric close (stream)
  (:documentation "Prevents further read and write operations on STREAM
causing them to raise STREAM-CLOSED-ERROR."))

(defmethod close ((stream stream))
  (setf (stream-open-p stream) nil))

(defmacro with-stream ((var stream) &body body)
  "Ensures STREAM gets closed returning from BODY with VAR bound to STREAM."
  (let ((s (gensym "STREAM-")))
    `(let ((,s ,stream))
       (unwind-protect (let ((,var ,s))
                         ,@body)
         (close ,s)))))

(defclass input-stream (stream)
  ()
  (:documentation "Subclass of STREAM supporting READ operations."))

(define-condition stream-input-error (stream-error)
  ()
  (:documentation "An error which is signalled when an input error
occurs on a stream."))

(defgeneric read (input-stream)
  (:documentation "Tries to read one element from STREAM.
Returns two values : the element or NIL if read failed;
and a state indicator which is
 NIL if read succeeded,
 :EOF if end of file was reached, or
 :NON-BLOCKING if read would block."))

(defgeneric read-sequence (input-stream seq &key start end)
  (:documentation "Reads elements from INPUT-STREAM into SEQ
from START to END. Returns two values :
 the number of elements read, and
 a state indicator which is
  NIL if READ-SEQUENCE succeeded
  :EOF if end of file was reached
  :NON-BLOCKING if read would block."))

(defgeneric read-sequence-until (input-stream end-element seq &key start end)
  (:documentation "Reads elements from INPUT-STREAM into SEQ
from START to END until END-ELEMENT is read. Returns two values :
 the number of elements read, and
 a state indicator which is
  NIL if READ-SEQUENCE-UNTIL succeeded
  :EOF if end of file was reached
  :NON-BLOCKING if read would block."))

(defmethod read-sequence ((stream input-stream) seq &key
                                                      (start 0)
                                                      (end (length seq)))
  (check-if-open stream)
  (let ((count 0))
    (loop
       (when (= start end)
         (return))
       (multiple-value-bind (element state) (read stream)
         (case state
           ((nil)
            (setf (aref seq start) element)
            (incf start)
            (incf count))
           ((:eof)
            (return (values count :eof)))
           ((:non-blocking)
            (return (values count :non-blocking)))
           (otherwise
            (error 'stream-input-error :stream stream)))))))

(defmethod read-sequence-until ((stream input-stream) end-element seq
                                &key (start 0) (end (length seq)))
  (check-if-open stream)
  (assert (typep end-element (stream-element-type stream)))
  (let ((count 0))
    (loop
       (when (= start end)
         (return))
       (multiple-value-bind (element state) (read stream)
         (case state
           ((nil)
            (setf (aref seq start) element)
            (incf start)
            (incf count)
            (when (eq element end-element)
              (return (values count nil))))
           ((:eof)
            (return (values count :eof)))
           ((:non-blocking)
            (return (values count :non-blocking)))
           (otherwise
            (error 'stream-input-error :stream stream)))))))

(defclass output-stream (stream)
  ()
  (:documentation "Subclass of STREAM supporting WRITE operations."))

(define-condition stream-output-error (stream-error)
  ()
  (:documentation "An error which is signalled when an output error
occurs on a stream."))

(defgeneric write (output-stream element)
  (:documentation "Tries to write one element to STREAM.
Returns a state indicator which is NIL if write succeeded,
:EOF if end of file was reached, or
:NON-BLOCKING if write would block."))

(defgeneric write-sequence (output-stream seq &key start end)
  (:documentation "Writes elements from SEQ from START to END
to OUTPUT-STREAM. Returns two values :
 the number of elements written, and
 a state indicator which is
  NIL if WRITE-SEQUENCE succeeded
  :EOF if end of file was reached
  :NON-BLOCKING if write would block."))

(defmethod write-sequence ((stream output-stream) seq &key
                                                        (start 0)
                                                        (end (length seq)))
  (check-if-open stream)
  (let ((count 0))
    (loop
       (when (= start end)
         (return))
       (let ((state (write stream (aref seq start))))
         (case state
           ((nil)
            (incf start)
            (incf count))
           ((:eof)
            (return (values count :eof)))
           ((:non-blocking)
            (return (values count :non-blocking)))
           (otherwise
            (error 'stream-output-error :stream stream)))))))

(defclass io-stream (input-stream output-stream)
  ())

(defvar *default-buffer-size*
  1024)

(deftype fixnum+ (&optional (start 0))
  `(integer ,start ,most-positive-fixnum))

(defclass buffered-input-stream (input-stream)
  ((input-buffer)
   (input-buffer-size :initarg :input-buffer-size
                      :initform *default-buffer-size*
                      :reader stream-input-buffer-size)
   (input-index :initform 0
                :accessor stream-input-index
                :type fixnum+)
   (input-length :initform 0
                 :accessor stream-input-length
                 :type fixnum+)))

(defgeneric make-stream-input-buffer (buffered-input-stream)
  (:documentation "Returns a new input buffer for stream."))

(defgeneric discard-stream-input-buffer (buffered-input-stream))

(defgeneric stream-input-buffer (buffered-input-stream)
  (:documentation "Returns the stream input buffer, calling
MAKE-STREAM-INPUT-BUFFER to create it if needed."))

(defgeneric (setf stream-input-buffer) (value buffered-input-stream)
  (:documentation "Sets the stream input buffer."))

(defgeneric stream-fill-input-buffer (buffered-input-stream)
  (:documentation "Fills the stream input buffer.
Returns NIL if successful, or
:EOF if end of file was reached, or
:NON-BLOCKING if operation would block."))

(defmethod make-stream-input-buffer ((stream buffered-input-stream))
  (make-array `(,(stream-input-buffer-size stream))
              :element-type (stream-element-type stream)))

(defmethod discard-stream-input-buffer ((stream buffered-input-stream))
  (setf (stream-input-buffer stream) nil))

(defmethod stream-input-buffer ((stream buffered-input-stream))
  (if (slot-boundp stream 'input-buffer)
      (slot-value stream 'input-buffer)
      (setf (slot-value stream 'input-buffer)
            (make-stream-input-buffer stream))))

(defmethod (setf stream-input-buffer) (value (stream buffered-input-stream))
  (setf (slot-value stream 'input-buffer) value))

(defgeneric stream-read-element-from-buffer (stream))

(defmethod stream-read-element-from-buffer ((stream buffered-input-stream))
  (let ((element (aref (stream-input-buffer stream)
                       (stream-input-index stream))))
    (assert (typep element (stream-element-type stream)))
    (incf (stream-input-index stream))
    (values element nil)))

(defmethod read ((stream buffered-input-stream))
  (check-if-open stream)
  (if (< (stream-input-index stream) (stream-input-length stream))
      (stream-read-element-from-buffer stream)
      (case (stream-fill-input-buffer stream)
        ((nil) (stream-read-element-from-buffer stream))
        ((:eof) (values nil :eof))
        ((:non-blocking) (values nil :non-blocking))
        (otherwise (error 'stream-input-error :stream stream)))))

(defmethod close :after ((stream buffered-input-stream))
  (discard-stream-input-buffer stream))

(defclass buffered-output-stream (output-stream)
  ((output-buffer)
   (output-buffer-size :initarg :output-buffer-size
                       :initform *default-buffer-size*
                       :reader stream-output-buffer-size)
   (output-index :initform 0
                 :accessor stream-output-index
                 :type fixnum+)
   (output-length :initform 0
                  :accessor stream-output-length
                  :type fixnum+))
  (:documentation "An output stream that buffers its writes until it
gets flushed."))

(defgeneric make-stream-output-buffer (buffered-output-stream)
  (:documentation "Returns a new output buffer for stream."))

(defgeneric discard-stream-output-buffer (buffered-output-stream))

(defgeneric stream-output-buffer (buffered-output-stream)
  (:documentation "Returns the stream output buffer, calling
MAKE-STREAM-OUTPUT-BUFFER to create it if needed."))

(defgeneric (setf stream-output-buffer) (value buffered-output-stream)
  (:documentation "Sets the stream output buffer."))

(defgeneric stream-flush-output-buffer (buffered-output-stream)
  (:documentation "Tries to flush once the stream output buffer. Returns
 NIL if successful, or
 :EOF if end of file was reached, or
 :NON-BLOCKING if operation would block."))

(defgeneric stream-write-element-to-buffer (stream element))

(defgeneric flush (buffered-output-stream)
  (:documentation "Flushes the output buffer of BUFFERED-OUTPUT-STREAM
by repeatedly calling STREAM-FLUSH-OUTPUT-BUFFER until empty. Returns
 NIL if output buffer was empty or emptied, or
 :EOF if end of file was reached, or
 :NON-BLOCKING if write would block."))

(defmethod make-stream-output-buffer ((stream buffered-output-stream))
  (make-array `(,(stream-output-buffer-size stream))
              :element-type (stream-element-type stream)))

(defmethod discard-stream-output-buffer ((stream buffered-output-stream))
  (setf (stream-output-buffer stream) nil))

(defmethod stream-output-buffer ((stream buffered-output-stream))
  (if (slot-boundp stream 'output-buffer)
      (slot-value stream 'output-buffer)
      (setf (slot-value stream 'output-buffer)
            (make-stream-output-buffer stream))))

(defmethod (setf stream-output-buffer) (value (stream buffered-output-stream))
  (setf (slot-value stream 'output-buffer) value))

(defmethod stream-write-element-to-buffer ((stream buffered-output-stream)
                                           element)
  (setf (aref (stream-output-buffer stream) (stream-output-length stream))
        element)
  (incf (stream-output-length stream))
  nil)

(defmethod write ((stream buffered-output-stream) element)
  (check-if-open stream)
  (assert (typep element (stream-element-type stream)))
  (if (< (stream-output-length stream) (stream-output-buffer-size stream))
      (stream-write-element-to-buffer stream element)
      (case (stream-flush-output-buffer stream)
        ((nil) (stream-write-element-to-buffer stream element))
        ((:eof) :eof)
        ((:non-blocking) :non-blocking)
        (otherwise (error 'stream-output-error :stream stream)))))

(defmethod flush ((stream buffered-output-stream))
  (loop
     (case (stream-flush-output-buffer stream)
       ((nil) (when (= 0 (stream-output-length stream))
                (return)))
       ((:eof) (return :eof))
       ((:non-blocking (return :non-blocking)))
       (otherwise (error 'stream-output-error :stream stream)))))

(defmethod close :before ((stream buffered-output-stream))
  (flush stream))

(defmethod close :after ((stream buffered-output-stream))
  (discard-stream-output-buffer stream))

(defclass sequence-input-stream (buffered-input-stream)
  ()
  (:documentation "A buffered input stream that reads from a sequence."))

(defmethod initialize-instance ((stream sequence-input-stream)
                                &rest initargs
                                &key sequence &allow-other-keys)
  (declare (ignore initargs)
           (type sequence sequence))
  (call-next-method)
  (setf (slot-value stream 'input-buffer) sequence))

(defmethod stream-element-type ((stream sequence-input-stream))
  (array-element-type (stream-input-buffer stream)))

(defmethod stream-input-buffer-size ((stream sequence-input-stream))
  (length (stream-input-buffer stream)))

(defmethod stream-input-length ((stream sequence-input-stream))
  (length (stream-input-buffer stream)))

(defmethod stream-fill-input-buffer ((stream sequence-input-stream))
  :eof)

(defmacro with-input-from-sequence ((var sequence) &body body)
  "Binds VAR to a new sequence input stream reading from SEQUENCE.
The stream is closed after BODY returns normally or before it is
aborted by a control transfer of some kind."
  (let ((stream (gensym "STREAM-")))
    `(let ((,stream (make-instance 'sequence-input-stream :sequence ,sequence)))
       (unwind-protect (let ((,var ,stream))
                         ,@body)
         (close ,stream)))))

(defmacro with-input-from-string ((var string) &body body)
  "Binds VAR to a new sequence input stream reading from STRING.
The stream is closed after BODY returns normally or before it is
aborted by a control transfer of some kind."
  `(with-input-from-sequence (,var (the string ,string))
     ,@body))

(defclass sequence-output-stream (buffered-output-stream)
  ()
  (:documentation "A buffered output stream that writes to a sequence."))

(defgeneric sequence-output-stream-sequence (sequence-output-stream)
  (:documentation "Returns the sequence that was written to
SEQUENCE-OUTPUT-STREAM."))

(defgeneric sequence-output-stream-reset (sequence-output-stream))

(defmethod sequence-output-stream-sequence ((stream sequence-output-stream))
  (subseq (stream-output-buffer stream) 0 (stream-output-length stream)))

(defmethod sequence-output-stream-reset ((stream sequence-output-stream))
  (setf (stream-output-length stream) 0))

(defmethod initialize-instance ((stream sequence-output-stream)
                                &rest initargs
                                &key element-type &allow-other-keys)
  (declare (ignore initargs))
  (call-next-method)
  (setf (slot-value stream 'output-buffer)
        (make-array `(,*default-buffer-size*)
                    :element-type element-type
                    :adjustable t)))

(defmethod stream-element-type ((stream sequence-output-stream))
  (array-element-type (stream-output-buffer stream)))

(defmethod stream-output-buffer-size ((stream sequence-output-stream))
  (length (stream-output-buffer stream)))

(defmethod flush ((stream sequence-output-stream))
  nil)

(defmethod stream-flush-output-buffer ((stream sequence-output-stream))
  (setf (slot-value stream 'output-buffer)
        (let ((output-buffer (stream-output-buffer stream)))
          (adjust-array output-buffer
                        `(,(+ (length output-buffer) *default-buffer-size*)))))
  nil)

(defmacro with-output-to-sequence ((var element-type) &body body)
  "Binds VAR to a new sequence output stream with element-type
ELEMENT-TYPE. Returns the sequence output stream sequence if
BODY returns normally. The stream is closed after BODY returns
normally or before it is aborted by a control transfer of some kind."
  (let ((stream (gensym "STREAM-")))
    `(let ((,stream (make-instance 'sequence-output-stream
                                   :element-type ,element-type)))
       (unwind-protect (let ((,var ,stream))
                         ,@body
                         (sequence-output-stream-sequence ,stream))
         (close ,stream)))))

(defclass string-output-stream (sequence-output-stream)
  ()
  (:default-initargs :element-type 'character))

(defgeneric string-output-stream-string (string-output-stream))

(defun string-output-stream (&key (element-type 'character)
                               (output-buffer-size *default-buffer-size*))
  (make-instance 'string-output-stream
                 :element-type element-type
                 :output-buffer-size output-buffer-size))

(defmethod string-output-stream-string ((stream string-output-stream))
  (sequence-output-stream-sequence stream))

(defmacro with-output-to-string ((var) &body body)
  "Binds VAR to a new sequence output stream with element-type
character. Returns the sequence output stream string if
BODY returns normally. The stream is closed after BODY returns
normally or before it is aborted by a control transfer of some kind."
  `(with-output-to-sequence (,var 'character)
     ,@body))

(defgeneric read-until (input-stream end-element)
  (:documentation "Reads elements from INPUT-STREAM from START to END
until END-ELEMENT is read. Returns two values :
 a sequence of elements read, and
 a state indicator which is
  NIL if READ-UNTIL succeeded
  :EOF if end of file was reached
  :NON-BLOCKING if read would block."))

(defgeneric read-line (input-stream))

(defmethod read-until ((stream input-stream) end-element)
  (block nil
    (let ((type (stream-element-type stream)))
      (assert (typep end-element type))
      (with-output-to-sequence (out type)
        (loop
           (multiple-value-bind (element state) (read stream)
             (case state
               ((nil)
                (write out element)
                (when (eq element end-element)
                  (return (values (sequence-output-stream-sequence out)
                                  nil))))
               ((:eof)
                (return (values (sequence-output-stream-sequence out)
                                :eof)))
               ((:non-blocking)
                (return (values (sequence-output-stream-sequence out)
                                :non-blocking)))
               (otherwise
                (error 'stream-input-error :stream stream)))))))))

(defmethod read-line ((stream input-stream))
  (read-until stream #\Newline))

#+test
(with-input-from-string (in "hello world !")
  (read-until in #\Space))

(defun shadowing-import-from ()
  `(:shadowing-import-from :cl-stream
                           ,@(package-shadowing-symbols :cl-stream)))

(defclass queue (io-stream)
  ((extend-by :initarg :extend-by
              :initform *default-buffer-size*
              :accessor queue-extend-by
              :type fixnum+)
   (buffer :reader queue-buffer
           :type array)
   (length :initform 0
           :accessor queue-length
           :type fixnum+)
   (read-index :initform 0
               :accessor queue-read-index
               :type fixnum+)
   (write-index :initform 0
                :accessor queue-write-index
                :type fixnum+)))

(defgeneric queue-first (queue))
(defgeneric (setf queue-first) (value queue))

(defmethod stream-blocking-p ((queue queue))
  nil)

(defmethod stream-element-type ((queue queue))
  (array-element-type (queue-buffer queue)))

(defmethod initialize-instance ((queue queue) &rest initargs
                                &key (element-type t)
                                  (size *default-buffer-size*))
  (declare (ignore initargs))
  (call-next-method)
  (let ((buffer (make-array `(,size) :element-type element-type)))
    (setf (slot-value queue 'buffer) buffer
          (queue-extend-by queue) size))
  queue)

(defmethod read ((queue queue))
  (let ((buffer (queue-buffer queue))
        (read-index (queue-read-index queue)))
    (cond ((= 0 (queue-length queue))
           (values nil :non-blocking))
          (t
           (let ((element (aref buffer read-index)))
             (decf (queue-length queue))
             (incf (queue-read-index queue))
             (when (= (queue-read-index queue) (length buffer))
               (setf (queue-read-index queue) 0))
             (values element nil))))))

(defmethod write ((queue queue) element)
  (let ((buffer (queue-buffer queue)))
    (let ((length (length buffer)))
      (when (= (queue-length queue) length)
        (let ((new-length (+ length (queue-extend-by queue))))
          (adjust-array buffer `(,new-length))
          (let ((n (- length (queue-write-index queue))))
            (dotimes (i n)
              (setf (aref buffer (+ (- new-length n) i))
                    (aref buffer (+ (queue-write-index queue) i))))
            (setf (queue-read-index queue) (- new-length n))))))
    (incf (queue-length queue))
    (setf (aref buffer (queue-write-index queue)) element)
    (incf (queue-write-index queue))
    (when (= (queue-write-index queue) (length buffer))
      (setf (queue-write-index queue) 0))
    nil))

(defmethod queue-first ((queue queue))
  (aref (queue-buffer queue) (queue-read-index queue)))

(defmethod (setf queue-first) (value (queue queue))
  (setf (aref (queue-buffer queue) (queue-read-index queue))
        value))

(defclass multi-buffered-output-stream (buffered-output-stream)
  ((underlying-stream :initarg :stream
                      :reader stream-underlying-stream
                      :type buffered-output-stream)))

(defmethod stream-element-type ((stream multi-buffered-output-stream))
  (stream-element-type (stream-underlying-stream stream)))

(defmethod make-stream-output-buffer ((stream multi-buffered-output-stream))
  (make-instance 'queue))

(defmethod write ((stream multi-buffered-output-stream) element)
  (check-if-open stream)
  (assert (typep element (stream-element-type stream)))
  (let ((underlying-stream (stream-underlying-stream stream)))
    (unless (< (stream-output-length underlying-stream)
               (stream-output-buffer-size underlying-stream))
      (when (< 0 (stream-output-index underlying-stream))
        (setf (stream-output-index stream)
              (stream-output-index underlying-stream)))
      (write (stream-output-buffer stream)
             (stream-output-buffer underlying-stream))
      (setf (stream-output-buffer underlying-stream)
            (make-stream-output-buffer underlying-stream)
            (stream-output-index underlying-stream) 0
            (stream-output-length underlying-stream) 0))
    (incf (stream-output-length stream))
    (write underlying-stream element)))

(defmethod stream-flush-output-buffer ((stream multi-buffered-output-stream))
  (let ((queue (when (slot-boundp stream 'output-buffer)
                 (stream-output-buffer stream)))
        (underlying-stream (stream-underlying-stream stream)))
    (if (or (null queue) (zerop (queue-length queue)))
        (stream-flush-output-buffer underlying-stream)
        (let ((last-buffer (stream-output-buffer underlying-stream))
              (last-buffer-length (stream-output-length underlying-stream))
              (first-buffer (queue-first queue)))
          (setf (stream-output-buffer underlying-stream) first-buffer
                (stream-output-index underlying-stream)
                (stream-output-index stream)
                (stream-output-length underlying-stream)
                (stream-output-buffer-size underlying-stream))
          (let ((r (stream-flush-output-buffer underlying-stream)))
            (when (= 0 (stream-output-length underlying-stream))
              (discard-stream-output-buffer underlying-stream)
              (setf (queue-first queue) nil)
              (read queue)
              (decf (stream-output-length stream)
                    (stream-output-buffer-size underlying-stream)))
            (setf (stream-output-index stream)
                  (stream-output-index underlying-stream)
                  (stream-output-buffer underlying-stream) last-buffer
                  (stream-output-index underlying-stream) 0
                  (stream-output-length underlying-stream) last-buffer-length)
            r)))))

(defun multi-buffered-output-stream (stream)
  (make-instance 'multi-buffered-output-stream :stream stream))
