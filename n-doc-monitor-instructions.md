# n-doc-monitor

## Goal and broad design idea

n-doc-monitor shall be a menu bar application for monitoring LuaTeX
processes. The goal is for the user to have an overview, which documents of the
current n-doc invocation are currently typeset and how many lualatex runs have
already passed. With longer documents, typesetting can take up to several
minutes per run. The app shall display the names of the documents that are
currently being processed, how many runs have already passed and how many runs
are still expected. The app shall live in the macOS menu bar. When selected, a
single panel shall appear to display information such as "ADV_TDS: Run 2,
ASE_ST_PP98: Run 3" etc. As it is not simple to guess the amount of lualatex
runs needed, we start by just counting the number of completed and active
runs. We do not employ guessing or heuristics about how many runs are
necessary. In later versions of the program, we might revisit this idea.

## n-doc process model

To start the typesetting process, the user invokes make. Depending on the target
provided (or the default target), make descends into the document directories of
the relevant documents. Within each directory, make calls itself and reads the
Makefile in that directory. It then calls latexmk. latexmk does the heavy
lifting, i.e. running laualatex, biber, makeindex and other programs. latexmk
orchestrates the different invocations of those tools and does its book-keeping,
when it has to call which tool.

## General design idea

The idea is that n-doc-monitor checks the running processes for a make
process. It must be discussed how to designate the proper process, maybe we can
pass an evironment variable that is used for nothing else? When n-doc-monitor
finds such a process, it shall check, whether there are child processes running
latexmk. Each these processes represents a single document being
processed. n-doc-monitor shall observe these processes and check for child
processes of latexmk. These would mainly be lualatex processes. n-doc-monitor
shall count these processes and use the accumulated data, so that it is able to
display information described above.

## Requirements

The app shall be written in Swift UI. It is specific for macOS, no need for iOS
or iPadOS compatibility.

The app shall only be usable when running make and its child processes natively
on the Mac. Docker is used primarily for CI runs. n-doc-monitor shall not
observe processes running in Docker.
