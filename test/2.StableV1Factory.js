const { expect } = require("chai");
const { ethers } = require("hardhat");

function getCreate2Address(
  factoryAddress,
  [tokenA, tokenB],
  bytecode
) {
  const [token0, token1] = tokenA < tokenB ? [tokenA, tokenB] : [tokenB, tokenA]
  const create2Inputs = [
    '0xff',
    factoryAddress,
    keccak256(solidityPack(['address', 'address'], [token0, token1])),
    keccak256(bytecode)
  ]
  const sanitizedInputs = `0x${create2Inputs.map(i => i.slice(2)).join('')}`
  return getAddress(`0x${keccak256(sanitizedInputs).slice(-40)}`)
}

describe("StableV1Factory", function () {

  let token;
  let usdt;
  let mim;
  let factory;
  let router;
  let pair;
  let owner;

  it("deploy stable coins", async function () {
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

  it("deploy StableV1Router and test factory address", async function () {
    const StableV1Router = await ethers.getContractFactory("StableV1Router01");
    router = await StableV1Router.deploy(factory.address);
    await router.deployed();

    expect(await router.factory()).to.equal(factory.address);
  });

  it("deploy pair via StableV1Factory", async function () {
    await factory.createPair(mim.address, usdt.address);
    expect(await factory.allPairsLength()).to.equal(1);
  });

  it("confirm pair for mim-usdt", async function () {
    const create2address = await router.pairFor(mim.address, usdt.address);
    const StableV1Pair = await ethers.getContractFactory("StableV1Pair");
    const address = await factory.getPair(mim.address, usdt.address);
    const allpairs0 = await factory.allPairs(0);
    pair = await StableV1Pair.attach(address);

    expect(pair.address).to.equal(create2address);
  });

  it("confirm tokens for mim-usdt", async function () {
    [token0, token1] = await router.sortTokens(usdt.address, mim.address);
    expect((await pair.token0()).toUpperCase()).to.equal(token0.toUpperCase());
    expect((await pair.token1()).toUpperCase()).to.equal(token1.toUpperCase());
  });

  it("mint tokens for pair mim-usdt", async function () {
    const usdt_1 = ethers.BigNumber.from("1000000");
    const mim_1 = ethers.BigNumber.from("1000000000000000000");
    const lp = await pair.lp(mim_1/1e12, usdt_1/1);
    await usdt.transfer(pair.address, usdt_1);
    await mim.transfer(pair.address, mim_1);
    await pair.mint(owner.address);
    expect(await pair.balanceOf(owner.address)).to.equal(lp);
  });
});
