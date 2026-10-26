# SYM is Ctrl on the ChaCha keyboard, so SYM+S (^S, XOFF) easily freezes the
# console output; switch software flow control off on the local consoles.
case $(tty 2>/dev/null) in
/dev/tty[0-9]*) stty -ixon ;;
esac
