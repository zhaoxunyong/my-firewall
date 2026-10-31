'use strict';
'require view';
'require rpc';
'require ui';
'require form';
'require uci';

function protocolText(protocol) {
	switch (protocol) {
	case 'tcp':
		return _('仅 TCP');
	case 'udp':
		return _('仅 UDP');
	default:
		return _('TCP 和 UDP');
	}
}

function actionInfo(action) {
	switch (action) {
	case 'accept':
		return { class: 'label label-success', text: _('接受') };
	case 'reject':
		return { class: 'label label-warning', text: _('拒绝') };
	default:
		return { class: 'label label-danger', text: _('丢弃') };
	}
}

function validIPAddress(value) {
	const parts = String(value || '').trim().split('/');
	const address = parts[0];
	const prefix = parts[1];

	if (parts.length > 2)
		return false;

	if (/^\d{1,3}(\.\d{1,3}){3}$/.test(address)) {
		const octets = address.split('.');

		for (let i = 0; i < octets.length; i++)
			if (+octets[i] > 255)
				return false;

		return prefix == null || (/^\d{1,2}$/.test(prefix) && +prefix <= 32);
	}

	if (address.indexOf(':') == -1 || !/^[0-9A-Fa-f:.]+$/.test(address))
		return false;

	if (prefix != null && (!/^\d{1,3}$/.test(prefix) || +prefix > 128))
		return false;

	try {
		new URL('http://[' + address + ']/');
		return true;
	}
	catch (e) {
		return false;
	}
}

function validMACAddress(value) {
	return /^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$/.test(String(value || '').trim());
}

function hostAddressList(value) {
	const list = Array.isArray(value) ? value : (value == null ? [] : [ value ]);

	return list.map(function(address) {
		if (address && typeof(address) == 'object')
			address = address.address;

		return String(address || '').trim();
	}).filter(function(address) {
		return address.length > 0;
	});
}

function addAddressChoice(choices, seen, value, label) {
	const key = String(value).toLowerCase();

	if (seen[key])
		return;

	seen[key] = true;
	choices.push({ value: value, label: label });
}

function hostAddressChoices(hosts, kind) {
	const choices = [];
	const seen = {};

	if (!hosts || typeof(hosts) != 'object')
		return choices;

	Object.keys(hosts).sort().forEach(function(rawMac) {
		const host = hosts[rawMac] || {};
		const mac = String(rawMac || '').trim().toUpperCase().replace(/-/g, ':');
		const name = String(host.name || '').trim();
		const ipv4 = hostAddressList(host.ipaddrs || host.ipv4).filter(validIPAddress);
		const ipv6 = hostAddressList(host.ip6addrs || host.ipv6).filter(validIPAddress);

		if (kind == 'mac') {
			if (!validMACAddress(mac))
				return;

			const hint = name || ipv4[0] || ipv6[0];
			addAddressChoice(choices, seen, mac,
				hint ? mac + ' (' + hint + ')' : mac);
			return;
		}

		ipv4.concat(ipv6).forEach(function(address) {
			const hint = name || mac;

			addAddressChoice(choices, seen, address.toLowerCase(),
				hint ? address + ' (' + hint + ')' : address);
		});
	});

	return choices;
}

function normalizeAddressValues(value, uppercase) {
	const values = [];

	L.toArray(value).forEach(function(value) {
		value = String(value || '').trim();

		if (!value)
			return;

		value = uppercase ? value.toUpperCase().replace(/-/g, ':') : value.toLowerCase();
		if (values.indexOf(value) == -1)
			values.push(value);
	});

	return values;
}

function addressValues(section_id, option, uppercase) {
	return normalizeAddressValues(uci.get('myfirewall', section_id, option), uppercase);
}

function addressNode(label, values) {
	const nodes = [ E('strong', label), ' ' ];

	values.forEach(function(value, index) {
		if (index)
			nodes.push(E('br'));

		nodes.push(E('var', value));
	});

	return E('span', nodes);
}

function sourceText(section_id) {
	const match = uci.get('myfirewall', section_id, 'match') || 'both';
	const macs = addressValues(section_id, 'src_mac', true);
	const ips = addressValues(section_id, 'src_ip', false);
	const nodes = [];

	if (macs.length && (match == 'mac' || match == 'both'))
		nodes.push(addressNode(_('MAC'), macs));

	if (ips.length && (match == 'ip' || match == 'both')) {
		if (nodes.length)
			nodes.push(E('br'));
		nodes.push(addressNode(_('IP'), ips));
	}

	return nodes.length ? nodes : [ E('em', _('未配置来源')) ];
}

function timeText(section_id) {
	const timed = (uci.get('myfirewall', section_id, 'timed') == '1');

	if (!timed)
		return E('span', _('全天'));

	const start = uci.get('myfirewall', section_id, 'start_time') || '--:--:--';
	const stop = uci.get('myfirewall', section_id, 'stop_time') || '--:--:--';
	const days = uci.get('myfirewall', section_id, 'weekdays');

	return E('span', [
		days ? E('span', [ days, E('br') ]) : '',
		E('var', '%s - %s'.format(start, stop))
	]);
}

const AddressDynamicList = form.DynamicList.extend({
	renderWidget: function(section_id, option_index, cfgvalue) {
		const value = (cfgvalue != null) ? cfgvalue : this.default;
		const choices = this.transformChoices();
		const widget = new ui.DynamicList(L.toArray(value), choices, {
			id: this.cbid(section_id),
			sort: this.keylist,
			optional: this.optional || this.rmempty,
			datatype: this.datatype,
			placeholder: choices ? null : this.custom_placeholder,
			select_placeholder: this.select_placeholder,
			custom_placeholder: this.custom_placeholder,
			validate: this.getValidator(section_id),
			disabled: (this.readonly != null) ? this.readonly : this.map.readonly
		});

		return widget.render();
	}
});

return view.extend({
	callHostHints: rpc.declare({
		object: 'luci-rpc',
		method: 'getHostHints',
		expect: { '': {} }
	}),

	load: function() {
		return Promise.all([
			uci.load('myfirewall'),
			L.resolveDefault(this.callHostHints(), {})
		]);
	},

	render: function(data) {
		const hosts = (data && data[1]) || {};
		let m, s, o;

		m = new form.Map('myfirewall', _('MyFirewall'),
			_('界面版本 r14。匹配指定 MAC/IP 设备前往非本机地址的 TCP/UDP 外部连接。规则由 fw4 和 nftables 执行，用于解决代理后自带防火墙规则不生效的问题。'));

		s = m.section(form.TypedSection, 'settings', _('全局设置'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('启用 MyFirewall'));
		o.default = o.enabled;
		o.rmempty = false;
		o.description = _('关闭后会移除 MyFirewall 生成的全部拦截规则。');

		s = m.section(form.GridSection, 'rule', _('通信规则'));
		s.addremove = true;
		s.anonymous = true;
		s.sortable = true;
		s.filterrow = true;

		s.sectiontitle = function(section_id) {
			return uci.get('myfirewall', section_id, 'name') || _('未命名规则');
		};

		o = s.option(form.Value, 'name', _('名称'));
		o.placeholder = _('例如：限制客厅电视外部访问');
		o.rmempty = false;
		o.modalonly = true;

		o = s.option(form.ListValue, 'match', _('来源匹配'));
		o.value('both', _('MAC 和 IP'));
		o.value('mac', _('仅 MAC'));
		o.value('ip', _('仅 IP'));
		o.default = 'both';
		o.rmempty = false;
		o.modalonly = true;
		o.description = _('选择“仅 MAC”或“仅 IP”只会显示对应地址输入框。');
		o.cfgvalue = function(section_id) {
			const value = uci.get('myfirewall', section_id, 'match');

			if (value)
				return value;

			const hasMac = addressValues(section_id, 'src_mac', false).length > 0;
			const hasIp = addressValues(section_id, 'src_ip', false).length > 0;

			if (hasMac && hasIp)
				return 'both';
			if (hasMac)
				return 'mac';
			if (hasIp)
				return 'ip';

			return 'both';
		};

		o = s.option(AddressDynamicList, 'src_mac', _('源 MAC 地址'));
		o.select_placeholder = _('— 选择已发现设备 —');
		o.custom_placeholder = _('— 自定义 —');
		o.rmempty = false;
		o.modalonly = true;
		o.depends('match', 'mac');
		o.depends('match', 'both');
		o.description = _('可从已发现设备中选择，也可输入自定义 MAC；可连续添加多个，规则命中其中任意一个。');
		hostAddressChoices(hosts, 'mac').forEach(function(choice) {
			o.value(choice.value, choice.label);
		});
		o.validate = function(section_id, value) {
			if (value == null || value == '')
				return true;

			const values = L.toArray(value);

			for (let i = 0; i < values.length; i++)
				if (!validMACAddress(values[i]))
					return _('请输入有效的 MAC 地址');

			return true;
		};
		o.write = function(section_id, value) {
			return this.super('write', [ section_id, normalizeAddressValues(value, true) ]);
		};

		o = s.option(AddressDynamicList, 'src_ip', _('源 IP 地址'));
		o.select_placeholder = _('— 选择已发现设备 —');
		o.custom_placeholder = _('— 自定义 —');
		o.rmempty = false;
		o.modalonly = true;
		o.depends('match', 'ip');
		o.depends('match', 'both');
		o.description = _('可从已发现设备中选择，也可输入自定义 IPv4/IPv6 地址；可连续添加多个，规则命中其中任意一个。');
		hostAddressChoices(hosts, 'ip').forEach(function(choice) {
			o.value(choice.value, choice.label);
		});
		o.validate = function(section_id, value) {
			if (value == null || value == '')
				return true;

			const values = L.toArray(value);

			for (let i = 0; i < values.length; i++) {
				const address = String(values[i]).trim();

				if (!validIPAddress(address))
					return _('请输入有效的 IPv4 或 IPv6 地址');
			}

			return true;
		};
		o.write = function(section_id, value) {
			return this.super('write', [ section_id, normalizeAddressValues(value, false) ]);
		};

		o = s.option(form.ListValue, 'protocol', _('协议'));
		o.value('tcp_udp', _('TCP 和 UDP'));
		o.value('tcp', _('仅 TCP'));
		o.value('udp', _('仅 UDP'));
		o.default = 'tcp_udp';
		o.rmempty = false;
		o.modalonly = true;
		o.cfgvalue = function(section_id) {
			const value = uci.get('myfirewall', section_id, 'protocol');

			if (value == 'tcp' || value == 'udp')
				return value;

			return 'tcp_udp';
		};

		o = s.option(form.ListValue, 'action', _('动作'));
		o.value('drop', _('丢弃 - 静默阻断'));
		o.value('reject', _('拒绝 - 返回失败响应'));
		o.value('accept', _('接受 - 匹配后跳出 MyFirewall'));
		o.default = 'drop';
		o.rmempty = false;
		o.modalonly = true;
		o.description = _('“接受”只结束 MyFirewall 当前链的匹配，仍会经过 OpenWrt 的其他防火墙链。');
		o.cfgvalue = function(section_id) {
			const value = uci.get('myfirewall', section_id, 'action');

			if (value == 'accept' || value == 'reject')
				return value;

			return 'drop';
		};

		o = s.option(form.DummyValue, '_match', _('匹配条件'));
		o.modalonly = false;
		o.textvalue = function(section_id) {
			return E('small', [
				E('div', [ E('strong', _('来源')), E('br') ].concat(sourceText(section_id))),
				E('div', { 'style': 'margin-top:.4em' }, [
					E('strong', _('协议')), ' ',
					E('var', protocolText(uci.get('myfirewall', section_id, 'protocol')))
				]),
				E('div', { 'style': 'margin-top:.4em' }, [
					E('strong', _('目标')), ' ',
					E('em', _('非本机地址'))
				])
			]);
		};

		o = s.option(form.DummyValue, '_action', _('动作'));
		o.modalonly = false;
		o.textvalue = function(section_id) {
			const info = actionInfo(uci.get('myfirewall', section_id, 'action'));

			return E('span', { 'class': info.class }, info.text);
		};

		o = s.option(form.DummyValue, '_time', _('时间'));
		o.modalonly = false;
		o.textvalue = function(section_id) {
			return E('small', timeText(section_id));
		};

		o = s.option(form.Flag, 'enabled', _('启用'));
		o.default = o.enabled;
		o.editable = true;
		o.modalonly = false;
		o.tooltip = function(section_id) {
			return uci.get('myfirewall', section_id, 'timed') == '1'
				? _('此规则启用了时间限制')
				: null;
		};

		o = s.option(form.Flag, 'timed', _('启用时间限制'));
		o.default = o.disabled;
		o.rmempty = false;
		o.modalonly = true;
		o.description = _('关闭时，此规则全天生效。');

		o = s.option(form.MultiValue, 'weekdays', _('星期'));
		o.multiple = true;
		o.display = 7;
		o.placeholder = _('每天');
		o.value('Mon', _('周一'));
		o.value('Tue', _('周二'));
		o.value('Wed', _('周三'));
		o.value('Thu', _('周四'));
		o.value('Fri', _('周五'));
		o.value('Sat', _('周六'));
		o.value('Sun', _('周日'));
		o.depends('timed', '1');
		o.modalonly = true;
		o.write = function(section_id, value) {
			return this.super('write', [ section_id, L.toArray(value).join(' ') ]);
		};

		o = s.option(form.Value, 'start_time', _('开始时间'));
		o.placeholder = _('HH:MM:SS');
		o.datatype = 'timehhmmss';
		o.rmempty = false;
		o.modalonly = true;
		o.depends('timed', '1');

		o = s.option(form.Value, 'stop_time', _('结束时间'));
		o.placeholder = _('HH:MM:SS');
		o.datatype = 'timehhmmss';
		o.rmempty = false;
		o.modalonly = true;
		o.depends('timed', '1');

		return m.render();
	}
});
