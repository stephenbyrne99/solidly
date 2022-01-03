const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("StableV1Factory", function () {

  let token;
  let usdt;
  let mim;
  let factory;
  let pair;
  let owner;

  beforeEach(async function () {
    [owner] = await ethers.getSigners();
    token = await ethers.getContractFactory("Token");
    usdt = await token.deploy('USDT', 'USDT', 6);
    mim = await token.deploy('MIM', 'MIM', 18);

    usdt.deployed();
    mim.deployed();
  });

  it("confirm usdt deployment", async function () {
    expect(await usdt.name()).to.equal("USDT");
  });

  it("confirm mim deployment", async function () {
    expect(await mim.name()).to.equal("MIM");
  });

  it("deploy StableV1Factory and test pair length", async function () {
    const StableV1Factory = await ethers.getContractFactory("StableV1Factory");
    factory = await StableV1Factory.deploy();
    await factory.deployed();

    expect(await factory.allPairsLength()).to.equal(0);
  });

  it("deploy pair via StableV1Factory", async function () {
    await factory.createPair(mim.address, usdt.address);
    expect(await factory.allPairsLength()).to.equal(1);
  });

  it("confirm pair for mim-usdt", async function () {
    const StableV1Pair = await ethers.getContractFactory("StableV1Pair");
    const address = await factory.allPairs(0);
    pair = await StableV1Pair.attach(address);

    expect(pair.address).to.equal('0x137e01aEaC83b7a0E8Fa494481AF2bf94CaE5B36');
  });

  it("mint tokens for pair mim-usdt", async function () {
    usdt.transfer(pair.address, ethers.BigNumber.from(1e6));
    mim.transfer(pair.address, ethers.BigNumber.from(1e18));
    console.log(await pair.name());
    await pair.mint(owner.address);
  });
});
