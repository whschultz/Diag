#!/bin/sh

export PATH="$PWD:$PATH"

# Even though Platypus can give us administrator privileges,
# it's still not root access, so we don't have access to
# stuff in other users' home directories.  Therefore, we
# launch Terminal and ask for root access.

open -b com.apple.Terminal "$PWD/platypus.command"

echo "Done.  You can quit this program now."
