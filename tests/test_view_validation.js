'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const source = fs.readFileSync(path.join(
	__dirname,
	'../package/luci-app-myfirewall/root/www/luci-static/resources/view/myfirewall/rules-v12.js'
), 'utf8');
const start = source.indexOf('function validIPAddress');
const end = source.indexOf('\n\nfunction normalizeAddressValues', start);
const context = { URL };

assert(start >= 0 && end > start, 'validIPAddress implementation not found');
vm.createContext(context);
vm.runInContext(source.slice(start, end) + '\nthis.validIPAddress = validIPAddress;', context);

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

console.log('MyFirewall view validation tests passed.');
