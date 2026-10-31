'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const source = fs.readFileSync(path.join(
	__dirname,
	'../package/luci-app-myfirewall/root/www/luci-static/resources/view/myfirewall/rules-v14.js'
), 'utf8');
const start = source.indexOf('function validIPAddress');
const end = source.indexOf('\n\nfunction normalizeAddressValues', start);
const context = { URL };

assert(start >= 0 && end > start, 'validIPAddress implementation not found');
vm.createContext(context);
vm.runInContext(source.slice(start, end) + [
	'this.validIPAddress = validIPAddress;',
	'this.validMACAddress = validMACAddress;',
	'this.hostAddressChoices = hostAddressChoices;'
].join('\n'), context);

for (const address of [
	'192.168.3.41',
	'192.168.3.0/24',
	'2001:db8::41',
	'2001:db8::/64'
])
	assert.strictEqual(context.validIPAddress(address), true, address);

for (const address of [
	'192.168.3.256',
	'192.168.3.0/33',
	'2001:db8::zz',
	'2001:db8::/129',
	''
])
	assert.strictEqual(context.validIPAddress(address), false, address);

for (const address of [ 'AA:BB:CC:DD:EE:FF', 'aa-bb-cc-dd-ee-ff' ])
	assert.strictEqual(context.validMACAddress(address), true, address);

for (const address of [ 'AA:BB:CC:DD:EE', 'GG:BB:CC:DD:EE:FF', '' ])
	assert.strictEqual(context.validMACAddress(address), false, address);

const hosts = {
	'bc:24:11:d3:af:ab': {
		name: '',
		ipaddrs: [ '192.168.3.1' ]
	},
	'c8:95:ce:a9:7f:d1': {
		name: 'dave-PC',
		ipaddrs: [ '192.168.3.2' ],
		ip6addrs: [ '2001:db8::2' ]
	}
};

assert.deepStrictEqual(
	Array.from(context.hostAddressChoices(hosts, 'mac'), choice => choice.value),
	[ 'BC:24:11:D3:AF:AB', 'C8:95:CE:A9:7F:D1' ]
);
assert.deepStrictEqual(
	Array.from(context.hostAddressChoices(hosts, 'mac'), choice => choice.label),
	[
		'BC:24:11:D3:AF:AB (192.168.3.1)',
		'C8:95:CE:A9:7F:D1 (dave-PC)'
	]
);
assert.deepStrictEqual(
	Array.from(context.hostAddressChoices(hosts, 'ip'), choice => choice.value),
	[ '192.168.3.1', '192.168.3.2', '2001:db8::2' ]
);
assert.deepStrictEqual(
	Array.from(context.hostAddressChoices(hosts, 'ip'), choice => choice.label),
	[
		'192.168.3.1 (BC:24:11:D3:AF:AB)',
		'192.168.3.2 (dave-PC)',
		'2001:db8::2 (dave-PC)'
	]
);

console.log('MyFirewall view validation tests passed.');
