###############################################################################
# x-access.tcl by asl_pls @ irc.underx.org #aslpls
# UnderX X Access Manager Script for Eggdrop
# Commands: 
#   !add <user> <access>   - Adds a user to X access list (Requires Op/Master)
#   !add aslpls 450       - Adds a user to X access list (Requires Op/Master)
#   !remove <user>        - Removes a user from X access list (Requires Op/Master)
#   !remove aslpls        - Removes a user from X access list (Requires Op/Master)
###############################################################################

namespace eval ::XAccess {
    # CHANGE THIS: Set the flag required to use these commands.
    # 'o' means Global Op, 'm' means Global Master. 
    variable required_flag "o|o"

    # Bindings for channel commands
    bind pub $required_flag !add    [namespace current]::pub_xadd
    bind pub $required_flag !remove [namespace current]::pub_xrem

    # Proc for adding a user
    proc pub_xadd {nick uhost hand chan arg} {
        set user [lindex [split $arg] 0]
        set level [lindex [split $arg] 1]

        if {$user eq "" || $level eq ""} {
            putquick "NOTICE $nick :Usage: !add <username> <access>"
            return 0
        }

        # Syntax: /msg x@channels.underx.org ADDUSER #channel user level
        putquick "PRIVMSG x@channels.underx.org :ADDUSER $chan $user $level"
        putquick "PRIVMSG $chan :Requested X to add \002$user\002 with access \002$level\002."
        return 1
    }

    # Proc for removing a user
    proc pub_xrem {nick uhost hand chan arg} {
        set user [lindex [split $arg] 0]

        if {$user eq ""} {
            putquick "NOTICE $nick :Usage: !remove <username>"
            return 0
        }

        # Syntax: /msg x@channels.underx.org REMUSER #channel user
        putquick "PRIVMSG x@channels.underx.org :REMUSER $chan $user"
        putquick "PRIVMSG $chan :Requested X to remove \002$user\002."
        return 1
    }

    putlog "Loaded: Undernet X Access Manager Script by asl_pls"
}
