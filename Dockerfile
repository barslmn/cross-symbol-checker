# syntax=docker/dockerfile:1
FROM alpine:3.17.0
ADD  cross-symbol-checker.sh /opt/cross-symbol-checker/
ADD  check-geneset.sh        /opt/cross-symbol-checker/
ADD  get-data.sh             /opt/cross-symbol-checker/
ADD  data/                   /opt/cross-symbol-checker/data
