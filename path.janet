### path.janet
###
### A library for path manipulation.
###
### Copyright 2019 © Calvin Rose

#
# Common
#

(def- ext-peg
  (peg/compile ~{:back (> -1 (+ (* ($) (set "\\/.")) :back))
                 :main :back}))

(defn ext
  "Get the file extension for a path."
  [path]
  (if-let [m (peg/match ext-peg path (length path))]
    (let [i (m 0)]
      (if (= (path i) 46)
        (string/slice path (m 0) -1)))))

(defn- redef
  "Redef a value, keeping all metadata."
  [from to]
  (setdyn (symbol to) (dyn (symbol from))))

#
# Generating Macros
#

(defmacro- decl-sep [pre sep] ~(def ,(symbol pre "/sep") ,sep))
(defmacro- decl-delim [pre d] ~(def ,(symbol pre "/delim") ,d))

(defmacro- decl-last-sep
  [pre sep]
  ~(def- ,(symbol pre "/last-sep-peg")
    (peg/compile '{:back (> -1 (+ (* ,sep ($)) :back))
                   :main :back})))

(defmacro- decl-basename
  [pre]
  ~(defn ,(symbol pre "/basename")
    "Gets the base file name of a path."
    [path]
    (if-let [m (peg/match
                 ,(symbol pre "/last-sep-peg")
                 path
                 (length path))]
      (let [[p] m]
        (string/slice path p -1))
      path)))

(defmacro- decl-parts
  [pre sep]
  ~(defn ,(symbol pre "/parts")
     "Split a path into its parts."
     [path]
     (string/split ,sep path)))

(defmacro- decl-normalize
  [pre sep sep-pattern lead]
  (defn capture-lead
    [& xs]
    [:lead (xs 0)])
  (def grammar
    ~{:span (some (if-not ,sep-pattern 1))
      :sep (some ,sep-pattern)
      :trailing-sep (? (* :sep (constant :sep)))
      :start (+ (replace '(* ,lead (? :span)) ,capture-lead)
                ':span)
      :main (* :start (any (* :sep ':span)) :trailing-sep)})
  (def peg (peg/compile grammar))
  ~(defn ,(symbol pre "/normalize")
     "Normalize a path. This removes . and .. in the
     path, as well as empty path elements."
     [path]
     (def accum @[])
     (def parts (peg/match ,peg path))
     (var seen 0)
     (each x parts
       (match x
         [:lead what] (array/push accum what)
         :sep (array/push accum "")
         "." nil
         ".." (if (= 0 seen)
                (array/push accum x)
                (do (-- seen) (array/pop accum)))
         (do (++ seen) (array/push accum x))))
     (def ret (string/join accum ,sep))
     (if (= "" ret) "." ret)))

(defmacro- decl-join
  [pre sep]
  ~(defn ,(symbol pre "/join")
     "Join path elements together."
     [& els]
     (,(symbol pre "/normalize") (string/join els ,sep))))

(defmacro- decl-abspath
  [pre]
  ~(defn ,(symbol pre "/abspath")
     "Coerce a path to be absolute."
     [path]
     (if (,(symbol pre "/abspath?") path)
       (,(symbol pre "/normalize") path)
       (,(symbol pre "/join") (or (dyn :path-cwd) (os/cwd)) path))))

#
# Posix
#

(defn posix/abspath?
  "Check if a path is absolute."
  [path]
  (string/has-prefix? "/" path))

(redef "ext" "posix/ext")
(decl-sep "posix" "/")
(decl-delim "posix" ":")
(decl-last-sep "posix" "/")
(decl-basename "posix")
(decl-parts "posix" "/")
(decl-normalize "posix" "/" "/" "/")
(decl-join "posix" "/")
(decl-abspath "posix")

#
# Windows
#

(def- abs-pat '(* (? (* (range "AZ" "az") `:`)) `\`))
(def- abs-peg (peg/compile abs-pat))
(defn win32/abspath?
  "Check if a path is absolute."
  [path]
  (not (not (peg/match abs-peg path))))

(redef "ext" "win32/ext")
(decl-sep "win32" "\\")
(decl-delim "win32" ";")
(decl-last-sep "win32" "\\")
(decl-basename "win32")
(decl-parts "win32" "\\")
(decl-normalize "win32" `\` (set `\/`) (* (? (* (range "AZ" "az") `:`)) `\`))
(decl-join "win32" "\\")
(decl-abspath "win32")

#
# Specialize for current OS
#

(def- syms
  ["ext"
   "sep"
   "delim"
   "basename"
   "abspath?"
   "abspath"
   "parts"
   "normalize"
   "join"])
(let [pre (if (= :windows (os/which)) "win32" "posix")]
  (each sym syms
    (redef (string pre "/" sym) sym)))
