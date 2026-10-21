# cqlsh without its "Failed to format value ..." reports, for presenting a demo live.
#
# cqlsh fails to format some values the demos select, a vector column and a (score, rank) pair of
# nulls among them, prints them raw instead, which reads correctly, and then reports each failure
# after the rows. This drops the reports and nothing else: errors from the server still show.
#
# Usage: uv run --no-project --python 3.12 --with scylla-cqlsh common/cqlsh-quiet.py [cqlsh args]
import os
import sys

from cqlsh import cqlsh

# The shell collects the failures in decoding_errors while printing the rows and reports them at the
# end; with this, what it collects goes to a throwaway list and it always finds none to report.
cqlsh.Shell.decoding_errors = property(lambda self: [], lambda self, value: None)

sys.exit(cqlsh.main(*cqlsh.read_options(sys.argv[1:], os.environ)))
