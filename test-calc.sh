#!/usr/bin/env bash
node -e "
const P = 569959033175447828700553127n; // from 246222302331793461998638951 / 0.00432
// amount was 1.525e36 initially. wait ... 
const max96 = 79228162514264337593543950335n;
const amount = 56995903317544782870055312731n;

const R = 50000000000n;
const rateDay1 = R * 86400n;
const rateDay2 = R * 172800n;
const PRECISION = 1000000000000000000n;

const b0 = amount;
const b1 = amount * (PRECISION + rateDay1) / PRECISION;
const b2 = amount * (PRECISION + rateDay2) / PRECISION;

console.log('int1', b1 - b0);
console.log('int2', b2 - b1);
"
