################################################################################
# chan_level_game.tcl - Manual Nickname-Based Channel Time Level Game
# chan_level_game.tcl by asl_pls @ irc.underx.org #aslpls
#
# Configurations:
#   .chanset #yourchannel +levelgame   <- Enable game on a per-channel basis.
#
# Commands:
#   !join                              <- Manually sign up for the game
#   !level [<nick>]                    <- Check your own or another user's level
################################################################################

package require Tcl 8.5

namespace eval ::ulvl {
    # --- Configuration ---
    variable db_file "channel_levels.db"
    variable join_trigger "!join"
    variable level_trigger "!level"
    variable flags "-"
    
    # Store persistent tracking matrix internally
    variable userdata [dict create]

    # Initialize custom channel flag so the script only runs where you want it
    setudef flag levelgame

    # Binds
    bind join - * [namespace current]::on_join
    bind pub $flags $join_trigger [namespace current]::pub_join
    bind pub $flags $level_trigger [namespace current]::pub_level
    bind time - "* * * * *" [namespace current]::minutely_tracker
    bind time - "00 */5 * * *" [namespace current]::show_top5_channel
    bind time - "00 */6 * * *" [namespace current]::update_channel_topic

    # Safe initialization and database load
    proc init {} {
        variable db_file
        variable userdata
        if {[file exists $db_file]} {
            set fp [open $db_file r]
            set data [read $fp]
            close $fp
            if {[catch {set userdata [dict create {*}$data]}]} {
                set userdata [dict create]
            }
        } else {
            set userdata [dict create]
        }
    }

    # Automatically grant Voice (+v) if a registered nickname joins the channel
    proc on_join {nick uhost hand chan} {
        if {![channel get $chan levelgame]} { return }
        variable userdata
        global botnick

        set clean_nick [string tolower $nick]

        # Check if the nickname is registered in our local database array
        if {[dict exists $userdata $clean_nick]} {
            if {[isop $botnick $chan]} {
                pushmode $chan +v $nick
            }
            puthelp "PRIVMSG $chan :\[LvlGame\] Welcome back \002$nick\002! You are logged into the game; tracking your time now."
        }
    }

    # Public command: !join
    proc pub_join {nick uhost hand chan arg} {
        if {![channel get $chan levelgame]} { return }
        variable userdata
        variable db_file
        global botnick

        set clean_nick [string tolower $nick]

        # Prevent duplicate entries
        if {[dict exists $userdata $clean_nick]} {
            puthelp "PRIVMSG $chan :$nick: You have already joined the game structure! Use !level to check your stats."
            return
        }

        # Initialize player record
        dict set userdata $clean_nick mins 0
        dict set userdata $clean_nick last_nick $nick

        # Save to disk
        set fp [open $db_file w]
        puts $fp $userdata
        close $fp

        # Grant voice mode instantly on sign-up if the bot is operator
        if {[isop $botnick $chan]} {
            pushmode $chan +v $nick
        }

        puthelp "PRIVMSG $chan :\[LvlGame\] Success! \002$nick\002 has officially entered the channel level game. Stay active to rank up!"
    }

    # Public command: !level [<nick>]
    proc pub_level {nick uhost hand chan arg} {
        if {![channel get $chan levelgame]} { return }
        variable userdata

        set target [string trim $arg]
        
        # Default to the person running the command if empty
        if {$target eq ""} {
            set target $nick
        }

        set clean_target [string tolower $target]

        if {[dict exists $userdata $clean_target mins]} {
            set mins [dict get $userdata $clean_target mins]
            set hours [expr {$mins / 60}]
            set lvl [get_level $mins]
            set rem_mins [expr {$mins % 60}]
            
            # Retrieve display casing preserved during logging
            set display_name [dict get $userdata $clean_target last_nick]
            
            puthelp "PRIVMSG $chan :\002$display_name\002 is \002Level $lvl\002 | Total Time: $hours hours and $rem_mins minutes."
        } else {
            puthelp "PRIVMSG $chan :$nick: \002$target\002 is not registered in the game yet. Type \002!join\002 to start tracking time!"
        }
    }

    # Every 1 minute, scan active channels and add time to registered nicknames
    proc minutely_tracker {min hour day month year} {
        variable userdata
        variable db_file

        set modified 0
        foreach chan [channels] {
            if {![channel get $chan levelgame]} { continue }
            if {![validchan $chan]} { continue }

            foreach nick [chanlist $chan] {
                if {[isbotnick $nick]} { continue }
                
                set clean_nick [string tolower $nick]

                # Check if this specific nick has opted into tracking
                if {[dict exists $userdata $clean_nick]} {
                    set current_mins [dict get $userdata $clean_nick mins]

                    incr current_mins
                    dict set userdata $clean_nick mins $current_mins
                    dict set userdata $clean_nick last_nick $nick
                    set modified 1

                    # Track progression milestones dynamically (Every 30 hours)
                    if {($current_mins % 60) == 0} {
                        set hours [expr {$current_mins / 60}]
                        if {($hours % 30) == 0 && $hours <= 600} {
                            set lvl [expr {$hours / 30}]
                            puthelp "PRIVMSG $chan :\002\[LEVEL UP\]\002 Congratulations to $nick! You have achieved \002Level $lvl\002 by spending $hours hours in the channel!"
                        }
                    }
                }
            }
        }

        if {$modified} {
            set fp [open $db_file w]
            puts $fp $userdata
            close $fp
        }
    }

    # Calculate Level programmatically (Level 1 = 30h, Level 2 = 60h, up to 20)
    proc get_level {mins} {
        set hours [expr {$mins / 60}]
        set lvl [expr {$hours / 30}]
        if {$lvl > 20} { set lvl 20 }
        return $lvl
    }

    # Helper process to rank top users
    proc get_top_users {limit} {
        variable userdata
        set sorted_list {}
        dict for {clean_nick data} $userdata {
            if {![dict exists $data mins]} { continue }
            set mins [dict get $data mins]
            set last_nick [dict get $data last_nick]
            lappend sorted_list [list $clean_nick $mins $last_nick]
        }
        return [lrange [lsort -integer -decreasing -index 1 $sorted_list] 0 [expr {$limit - 1}]]
    }

    # Output scoreboard to every active channel every 5 hours
    proc show_top5_channel {min hour day month year} {
        set top5 [get_top_users 5]
        if {[llength $top5] == 0} { return }

        foreach chan [channels] {
            if {![channel get $chan levelgame]} { continue }
            
            puthelp "PRIVMSG $chan :\002--- Top 5 Channel Time Levels (Active Game Players) ---\002"
            set rank 1
            foreach user $top5 {
                lassign $user clean_nick mins last_nick
                set hours [expr {$mins / 60}]
                set lvl [get_level $mins]
                puthelp "PRIVMSG $chan :${rank}. \002$last_nick\002 - Level $lvl \[$hours Hours Spent\]"
                incr rank
            }
        }
    }

    # Synchronize top user metrics directly into the channel topic every 6 hours
    proc update_channel_topic {min hour day month year} {
        global botnick
        set top1 [get_top_users 1]
        if {[llength $top1] == 0} { return }
        
        lassign [lindex $top1 0] clean_nick mins last_nick
        set hours [expr {$mins / 60}]
        set lvl [get_level $mins]

        foreach chan [channels] {
            if {![channel get $chan levelgame]} { continue }
            if {![validchan $chan] || ![isop $botnick $chan]} { continue }

            set base_topic "Welcome! Chat & Level up by typing !join to enter the time tracking game."
            set dynamic_ticker " | \002Current Top User:\002 $last_nick (Lvl $lvl with $hours Hours!)"
            
            puthelp "TOPIC $chan :${base_topic}${dynamic_ticker}"
            putlog "\[LvlGame\] Pushed updated time levels to topic framework on $chan"
        }
    }

    init
}

 putlog "channel_level_up_game.tcl loaded successfully. By asl_pls @ irc.underx.org #aslpls"
