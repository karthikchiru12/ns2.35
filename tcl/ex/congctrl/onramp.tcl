# Author : Anirudh Sivaraman
# Star topology with basestation at the centre.

# Create a simulator object
set ns [ new Simulator ]

# Tracing: DO NOT MOVE THIS BELOW
set trace_file [ open cell-link.tr w ]

# required for reading cmd line arguments
unset opt

# Clean up procedures
proc finish { sim_object trace_file } {
  global opt stats onoff_server num_users
  if {$opt(enable_on_off) == "true"} {
    for {set i 0} {$i < $num_users} {incr i} {
      set rapp $onoff_server($i)
      if { [$rapp set state_] == ON} {
        # If the current state is ON, then we have one more set of stats to update.
        # Otherwise, we're all set and there's nothing to update.
        set nbytes [$rapp set nbytes_]
        set ontime [expr [$sim_object now] - [$rapp set laststart_] ]
        set cumrtt [$rapp set cumrtt_]
        set numsamples [$rapp set numsamples_]
        set rttsamples [$rapp set rtt_samples_]
        set srcid [$rapp set srcid_]
        $stats($srcid) update $nbytes $ontime $cumrtt $numsamples $rttsamples
      }
      $stats($srcid) showstats True
    }
  }
  $sim_object flush-trace
  close $trace_file
  exit 0
}

# read default constants from config file
source onrampconf/configuration.tcl

# Print out Usage
proc Usage {} {
  global opt argv0
  foreach name [ array names opt ] {
    puts -nonewline stderr " \[-"
    puts -nonewline stderr [ format "%20s" $name ]
    puts -nonewline stderr " :\t"
    puts -nonewline stderr [ format "%15.15s"  $opt($name) ]
    puts -nonewline stderr "\]\n"
  }
}

# Override defaults using the command line if desired
proc Getopt {} {
  global opt argc argv argv0
  if {$argc == 0} {
    puts stderr "Usage : $argv0 \n"
    Usage
    exit 1
  }
  for {set i 0} {$i < $argc} {incr i} {
    set key [lindex $argv $i]
    if ![string match {-*} $key] continue
    set key [string range $key 1 end]
    set val [lindex $argv [incr i]]
    puts stderr "Parameter $key"
    assert ( [ info exists opt($key)] );
    puts stderr "Value $val"
    set opt($key) $val
  }
}

Getopt
Usage

# create basestation
set basestation [ $ns node ]

# Determine number of users
set num_users $opt(num_tcp)

# Pick appropriate ensemble_scheduler
if { $opt(ensemble_scheduler) == "pf" } {
  set ensemble_scheduler [ new PFScheduler $num_users 0.0 $opt(cdma_slot_duration) $opt(cdma_ewma_slots) $opt(alpha) $opt(sub_qdisc) ]
} elseif { $opt(ensemble_scheduler) == "fcfs" } {
  set ensemble_scheduler [ new FcfsScheduler $num_users 0.0 ]
}

# Create rate generator
set rate_generator [ new EnsembleRateGenerator $opt(link_trace) ]; 
set users_in_trace [ $rate_generator get_users_ ]
puts stderr "Num users is $num_users, users_in_trace $users_in_trace users "
assert ( $num_users == $users_in_trace );

# Unique ID
set counter 0

# Link creation
proc create_link {ns  bw latency sender receiver qdisc user_id} {
  global opt
  set q_args [ list $opt(_K) $opt(headroom) $opt(iter) $user_id ]
  if { $qdisc == "SFD" } {
    $ns simplex-link $sender $receiver [ bw_parse $bw ]  $latency $qdisc $q_args
  } else {
    $ns simplex-link $sender $receiver [ bw_parse $bw ]  $latency $qdisc
  }
  $ns simplex-link $receiver $sender [ bw_parse $bw ]  $latency DropTail
}

# DropTail feedback queue, make sure you have sufficient buffering
Queue set limit_ 10000

# Neuter queue
proc neuter_queue {queue} {
  # block queues
  $queue set blocked_ 1
  $queue set unblock_on_resume_ 0

  # Infinite buffer
  $queue set limit_ 10000

  # Deactivate forward queue
  $queue deactivate_queue
}

# Add queue and link to ensemble scheduler
proc attach_to_scheduler {scheduler user queue link} {
  puts stderr "Adding user $user to scheduler"
  $scheduler attach-queue $queue $user
  $scheduler attach-link  $link  $user
  # Deactivate link
  $link deactivate_link
}

# Setup SFD
proc setup_sfd {queue scheduler} {
  $queue attach-sched $scheduler
}

# TCP connections
source setup_onramp_tcp_connections.tcl

# Activate scheduler
$ensemble_scheduler activate-link-scheduler

# Activate rate_generator
$rate_generator activate-rate-generator

# Run simulation
ns-random $opt(seed)
$ns at $opt(duration) "finish $ns $trace_file"
$ns run
