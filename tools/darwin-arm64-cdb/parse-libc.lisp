;;;; Parse libc .ffi → *.cdb under ccl:darwin-arm64-headers;libc;
;;;;
;;;;   # BACK UP first — install-new-db-files replaces *.cdb in place
;;;;   cp darwin-arm64-headers/libc/*.cdb /tmp/libc-cdb-backup/
;;;;   ./darm64cl --no-init --batch < tools/darwin-arm64-cdb/parse-libc.lisp
;;;;
;;;; Core-only .ffi sets produce a small CDB; restore the bring-up copy
;;;; unless coverage is intentionally complete (see README.md).
(in-package :ccl)
(require "PARSE-FFI")
(format t "~&;; parse-standard-ffi-files \"libc\"~%")
(parse-standard-ffi-files "libc")
(format t "~&;; PARSE-LIBC-OK~%")
(quit)
