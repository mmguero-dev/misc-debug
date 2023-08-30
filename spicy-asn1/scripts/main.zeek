@load base/protocols/conn/removal-hooks

module ASN;

export {
	## Log stream identifier.
	redef enum Log::ID += { LOG };

	## Record type containing the column fields of the ASN log.
	type Info: record {
		## Timestamp for when the activity happened.
		ts: time &log;
		## Unique ID for the connection.
		uid: string &log;
		## The connection's 4-tuple of endpoint addresses/ports.
		id: conn_id &log;

		payload: string &optional &log;
	};

	## A default logging policy hook for the stream.
	global log_policy: Log::PolicyHook;

	## Default hook into ASN logging.
	global log_asn: event(rec: Info);

	## ASN finalization hook.
	global finalize_asn: Conn::RemovalHook;
}

redef record connection += {
	asn: Info &optional;
};

export {
    const asn1_ports_tcp: set[port] = { 12345/tcp } &redef;
    const asn1_ports_udp: set[port] = { 12345/udp } &redef;
}
redef likely_server_ports += { asn1_ports_tcp, asn1_ports_udp };

event zeek_init() &priority=5 {
	Analyzer::register_for_ports(Analyzer::ANALYZER_SPICY_ASN1_TCP, asn1_ports_tcp);
	Analyzer::register_for_ports(Analyzer::ANALYZER_SPICY_ASN1_UDP, asn1_ports_udp);

	Log::create_stream(ASN::LOG, [$columns=Info, $ev=log_asn, $path="asn1", $policy=log_policy]);
}

hook set_session(c: connection) {
	if ( c?$asn )
		return;

	c$asn = Info($ts=network_time(), $uid=c$uid, $id=c$id);
	Conn::register_removal_hook(c, finalize_asn);
}

function emit_log(c: connection) {
	if ( ! c?$asn )
		return;

	Log::write(ASN::LOG, c$asn);
	delete c$asn;
}

event ASN::message(c: connection, is_orig: bool, payload: string) {
	hook set_session(c);

	local info = c$asn;
	info$payload = payload;

	emit_log(c);
}


hook finalize_asn(c: connection) {
	;
}
