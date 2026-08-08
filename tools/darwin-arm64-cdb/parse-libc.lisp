;;;; Parse libc .ffi → *.cdb under ccl:darwin-arm64-headers;libc;
;;;;
;;;;   # BACK UP first — install-new-db-files replaces *.cdb in place
;;;;   cp darwin-arm64-headers/libc/*.cdb /tmp/libc-cdb-backup/
;;;;   ./darm64cl --stack-size 16M --thread-stack-size 16M --no-init --batch \
;;;;     < tools/darwin-arm64-cdb/parse-libc.lisp
;;;;
;;;; Prefer tools/darwin-arm64-cdb/libc-populate.sh (full) over core-only.
;;;; Skip math.h (see libc-populate.sh) — its .ffi overflows the FFI reader.
;;;; Until counts match bring-up, restore the x86-copy CDB after validating.
(in-package :ccl)
(require "PARSE-FFI")
(format t "~&;; parse-standard-ffi-files \"libc\"~%")
(parse-standard-ffi-files "libc")
(format t "~&;; PARSE-LIBC-OK~%")
(quit)
