# Maik Justus < fg # mjustus : de >, based on bo105.nas by Melchior FRANZ, < mfranz # aon : at >

if (!contains(globals, "cprint")) {
	globals.cprint = func {};
}

var optarg = aircraft.optarg;
var makeNode = aircraft.makeNode;

var sin = func(a) { math.sin(a * math.pi / 180.0) }
var cos = func(a) { math.cos(a * math.pi / 180.0) }
var pow = func(v, w) { math.exp(math.ln(v) * w) }
var npow = func(v, w) { math.exp(math.ln(abs(v)) * w) * (v < 0 ? -1 : 1) }
var clamp = func(v, min = 0, max = 1) { v < min ? min : v > max ? max : v }
var normatan = func(x) { math.atan2(x, 1) * 2 / math.pi }




# timers ============================================================
var turbine_timer = aircraft.timer.new("/sim/time/hobbs/turbines", 10);
aircraft.timer.new("/sim/time/hobbs/helicopter", nil).start();

# strobes ===========================================================
var strobe_switch = props.globals.getNode("controls/lighting/strobe", 1);
aircraft.light.new("sim/model/s58/lighting/strobe-top", [0.05, 1.00], strobe_switch);
aircraft.light.new("sim/model/s58/lighting/strobe-bottom", [0.05, 1.03], strobe_switch);

# beacons ===========================================================
var beacon_switch = props.globals.getNode("controls/lighting/beacon", 1);
aircraft.light.new("sim/model/s58/lighting/beacon-top", [0.62, 0.62], beacon_switch);
aircraft.light.new("sim/model/s58/lighting/beacon-bottom", [0.63, 0.63], beacon_switch);


# nav lights ========================================================
var nav_light_switch = props.globals.getNode("controls/lighting/nav-lights", 1);
var visibility = props.globals.getNode("environment/visibility-m", 1);
var sun_angle = props.globals.getNode("sim/time/sun-angle-rad", 1);
var nav_lights = props.globals.getNode("sim/model/s58/lighting/nav-lights", 1);

var nav_light_loop = func {
	if (nav_light_switch.getValue()) {
		nav_lights.setValue(visibility.getValue() < 5000 or sun_angle.getValue() > 1.4);
	} else {
		nav_lights.setValue(0);
	}
	settimer(nav_light_loop, 3);
}

settimer(nav_light_loop, 0);






# engines/rotor =====================================================
var state = props.globals.getNode("sim/model/s58/state");
var engine = props.globals.getNode("sim/model/s58/engine");
var rotor = props.globals.getNode("controls/engines/engine/magnetos");
var rotor_rpm = props.globals.getNode("rotors/main/rpm");
var torque = props.globals.getNode("rotors/gear/total-torque", 1);
var collective = props.globals.getNode("controls/engines/engine[0]/throttle");
var turbine = props.globals.getNode("sim/model/s58/turbine-rpm-pct", 1);
var torque_pct = props.globals.getNode("sim/model/s58/torque-pct", 1);
var stall = props.globals.getNode("rotors/main/stall", 1);
var stall_filtered = props.globals.getNode("rotors/main/stall-filtered", 1);
var torque_sound_filtered = props.globals.getNode("rotors/gear/torque-sound-filtered", 1);
var target_rel_rpm = props.globals.getNode("controls/rotor/reltarget", 1);
var max_rel_torque = props.globals.getNode("controls/rotor/maxreltorque", 1);


# 0 off
# 1 engine startup
# 2 engine startup with small torque on rotor
# 3 engine idle
# 4 engine accel
# 5 engine sound loop


var update_state = func {
	var s = state.getValue();
	var new_state = arg[0];
	if (new_state == (s+1)) {
		state.setValue(new_state);
		if (new_state == (1)) {
			settimer(func { update_state(2) }, 2);
			interpolate(engine, 0.03, 0.1, 0.002, 0.3, 0.02, 0.1, 0.003, 0.7, 0.03, 0.1, 0.01, 0.7);
		} else {
			if (new_state == (2)) {
				settimer(func { update_state(3) }, 3);
				rotor.setValue(1);
				max_rel_torque.setValue(0.01);
				target_rel_rpm.setValue(0.002);
				interpolate(engine, 0.05, 0.2, 0.03, 1, 0.07, 0.1, 0.04, 0.9, 0.02, 0.5);
			} else { 
				if (new_state == (3)) {
					if (rotor_rpm.getValue() > 100) {
						#rotor is running at high rpm, so accel. engine faster
						max_rel_torque.setValue(1);
						target_rel_rpm.setValue(1.03);
						state.setValue(5);
						interpolate(engine, 1.03, 10);
					} else {
						settimer(func { update_state(4) }, 7);
						max_rel_torque.setValue(0.05);
						target_rel_rpm.setValue(0.02);
						interpolate(engine, 0.07, 0.1, 0.03, 0.25, 0.075, 0.2, 0.08, 1, 0.06,2);
					}
				} else {
					if (new_state == (4)) {
						settimer(func { update_state(5) }, 30);
						max_rel_torque.setValue(0.25);
						target_rel_rpm.setValue(0.8);
					} else {
							if (new_state == (5)) {
							max_rel_torque.setValue(1);
							target_rel_rpm.setValue(1.03);
						}
					}
				}
			}
		}
	}
}

var engines = func {
	if (props.globals.getNode("sim/crashed",1).getBoolValue()) {return; }
	var s = state.getValue();
	if (arg[0] == 1) {
		if (s == 0) {
			update_state(1);
		}
	} else {
		rotor.setValue(0);				# engines stopped
		state.setValue(0);
		interpolate(engine, 0, 4);
	}
}

var update_engine = func {
	if (state.getValue() > 3 ) {
		interpolate (engine,  clamp( rotor_rpm.getValue() / 235 ,
								0.05, target_rel_rpm.getValue() ), 0.25 );
	}
}

# torquemeter
var torque_val = 0;
torque.setDoubleValue(0);

var update_torque = func(dt) {
	var f = dt / (0.2 + dt);
	torque_val = torque.getValue() * f + torque_val * (1 - f);
	torque_pct.setDoubleValue(torque_val / 5300);
}




# sound =============================================================

# stall sound
var stall_val = 0;
stall.setDoubleValue(0);

var update_stall = func(dt) {
	var s = stall.getValue();
	if (s < stall_val) {
		var f = dt / (0.3 + dt);
		stall_val = s * f + stall_val * (1 - f);
	} else {
		stall_val = s;
	}
	var c = collective.getValue();
	stall_filtered.setDoubleValue(stall_val + 0.006 * (1 - c));
}


# modify sound by torque
var torque_val = 0;

var update_torque_sound_filtered = func(dt) {
	var t = torque.getValue();
	t = clamp(t * 0.000001);
	t = t*0.25 + 0.75;
	var r = clamp(rotor_rpm.getValue()*0.02-1);
	torque_sound_filtered.setDoubleValue(t*r);
}





# skid slide sound
var Skid = {
	new : func(n) {
		var m = { parents : [Skid] };
		var soundN = props.globals.getNode("sim/sound", 1).getChild("slide", n, 1);
		var gearN = props.globals.getNode("gear", 1).getChild("gear", n, 1);

		m.compressionN = gearN.getNode("compression-norm", 1);
		m.rollspeedN = gearN.getNode("rollspeed-ms", 1);
		m.frictionN = gearN.getNode("ground-friction-factor", 1);
		m.wowN = gearN.getNode("wow", 1);
		m.volumeN = soundN.getNode("volume", 1);
		m.pitchN = soundN.getNode("pitch", 1);

		m.compressionN.setDoubleValue(0);
		m.rollspeedN.setDoubleValue(0);
		m.frictionN.setDoubleValue(0);
		m.volumeN.setDoubleValue(0);
		m.pitchN.setDoubleValue(0);
		m.wowN.setBoolValue(1);
		m.self = n;
		return m;
	},
	update : func {
		me.wowN.getBoolValue() or return;
		var rollspeed = abs(me.rollspeedN.getValue());
		me.pitchN.setDoubleValue(rollspeed * 0.6);

		var s = normatan(20 * rollspeed);
		var f = clamp((me.frictionN.getValue() - 0.5) * 2);
		var c = clamp(me.compressionN.getValue() * 2);
		me.volumeN.setDoubleValue(s * f * c * 2);
		#if (!me.self) {
		#	cprint("33;1", sprintf("S=%0.3f  F=%0.3f  C=%0.3f  >>  %0.3f", s, f, c, s * f * c));
		#}
	},
};

var skid = [];
for (var i = 0; i < 3; i += 1) {
	append(skid, Skid.new(i));
}

var update_slide = func {
	forindex (var i; skid) {
		skid[i].update();
	}
}



# crash handler =====================================================
#var load = nil;
var crash = func {
	if (arg[0]) {
		# crash
		setprop("rotors/main/rpm", 0);
		setprop("rotors/main/blade[0]/flap-deg", -60);
		setprop("rotors/main/blade[1]/flap-deg", -50);
		setprop("rotors/main/blade[2]/flap-deg", -40);
		setprop("rotors/main/blade[3]/flap-deg", -30);
		setprop("rotors/main/blade[0]/incidence-deg", -30);
		setprop("rotors/main/blade[1]/incidence-deg", -20);
		setprop("rotors/main/blade[2]/incidence-deg", -50);
		setprop("rotors/main/blade[3]/incidence-deg", -55);
		setprop("rotors/tail/rpm", 0);
		strobe_switch.setValue(0);
		beacon_switch.setValue(0);
		nav_light_switch.setValue(0);
		rotor.setValue(0);
		torque_pct.setValue(torque_val = 0);
		stall_filtered.setValue(stall_val = 0);
		state.setValue(0);

	} else {
		# uncrash (for replay)
		setprop("rotors/tail/rpm", 1500);
		setprop("rotors/main/rpm", 235);
		for (i = 0; i < 4; i += 1) {
			setprop("rotors/main/blade[" ~ i ~ "]/flap-deg", 0);
			setprop("rotors/main/blade[" ~ i ~ "]/incidence-deg", 0);
		}
		strobe_switch.setValue(1);
		beacon_switch.setValue(1);
		rotor.setValue(1);
		state.setValue(5);
	}
}




# "manual" rotor animation for flight data recorder replay ============
var rotor_step = props.globals.getNode("sim/model/s58/rotor-step-deg");
var blade1_pos = props.globals.getNode("rotors/main/blade[0]/position-deg", 1);
var blade2_pos = props.globals.getNode("rotors/main/blade[1]/position-deg", 1);
var blade3_pos = props.globals.getNode("rotors/main/blade[2]/position-deg", 1);
var blade4_pos = props.globals.getNode("rotors/main/blade[3]/position-deg", 1);
var rotorangle = 0;

var rotoranim_loop = func {
	i = rotor_step.getValue();
	if (i >= 0.0) {
		blade1_pos.setValue(rotorangle);
		blade2_pos.setValue(rotorangle + 90);
		blade3_pos.setValue(rotorangle + 180);
		blade4_pos.setValue(rotorangle + 270);
		rotorangle += i;
		settimer(rotoranim_loop, 0.1);
	}
}

var init_rotoranim = func {
	if (rotor_step.getValue() >= 0.0) {
		settimer(rotoranim_loop, 0.1);
	}
}










# view management ===================================================

var elapsedN = props.globals.getNode("/sim/time/elapsed-sec", 1);
var flap_mode = 0;
var down_time = 0;
controls.flapsDown = func(v) {
	if (!flap_mode) {
		if (v < 0) {
			down_time = elapsedN.getValue();
			flap_mode = 1;
			dynamic_view.lookat(
					5,     # heading left
					-20,   # pitch up
					0,     # roll right
					0.2,   # right
					0.6,   # up
					0.85,  # back
					0.2,   # time
					55,    # field of view
			);
		} elsif (v > 0) {
			flap_mode = 2;
			var p = "/sim/view/dynamic/enabled";
			setprop(p, !getprop(p));
		}

	} else {
		if (flap_mode == 1) {
			if (elapsedN.getValue() < down_time + 0.2) {
				return;
			}
			dynamic_view.resume();
		}
		flap_mode = 0;
	}
}


# register function that may set me.heading_offset, me.pitch_offset, me.roll_offset,
# me.x_offset, me.y_offset, me.z_offset, and me.fov_offset
#
dynamic_view.register(func {
	var lowspeed = 1 - normatan(me.speedN.getValue() / 50);
	var r = sin(me.roll) * cos(me.pitch);

	me.heading_offset =						# heading change due to
		(me.roll < 0 ? -50 : -30) * r * abs(r);			#    roll left/right

	me.pitch_offset =						# pitch change due to
		(me.pitch < 0 ? -50 : -50) * sin(me.pitch) * lowspeed	#    pitch down/up
		+ 15 * sin(me.roll) * sin(me.roll);			#    roll

	me.roll_offset =						# roll change due to
		-15 * r * lowspeed;					#    roll
});




# main() ============================================================
var delta_time = props.globals.getNode("/sim/time/delta-realtime-sec", 1);
var adf_rotation = props.globals.getNode("/instrumentation/adf/rotation-deg", 1);
var hi_heading = props.globals.getNode("/instrumentation/heading-indicator/indicated-heading-deg", 1);

var main_loop = func {
	# adf_rotation.setDoubleValue(hi_heading.getValue());

	var dt = delta_time.getValue();
	update_torque(dt);
	update_stall(dt);
	update_torque_sound_filtered(dt);
	update_slide();
	update_engine();
	settimer(main_loop, 0);
}


var crashed = 0;
var variant = nil;
var doors = nil;
var config_dialog = nil;


# initialization
setlistener("/sim/signals/fdm-initialized", func {

	init_rotoranim();
	collective.setDoubleValue(1);

	setlistener("/sim/signals/reinit", func {
		cmdarg().getBoolValue() and return;
		cprint("32;1", "reinit");
		turbine_timer.stop();
		collective.setDoubleValue(1);
		variant.scan();
		crashed = 0;
	});

	setlistener("sim/crashed", func {
		cprint("31;1", "crashed ", cmdarg().getValue());
		turbine_timer.stop();
		if (cmdarg().getBoolValue()) {
			crash(crashed = 1);
		}
	});

	setlistener("/sim/freeze/replay-state", func {
		cprint("33;1", cmdarg().getValue() ? "replay" : "pause");
		if (crashed) {
			crash(!cmdarg().getBoolValue())
		}
	});

	# the attitude indicator needs pressure
	# settimer(func { setprop("engines/engine/rpm", 3000) }, 8);

	main_loop();
});

