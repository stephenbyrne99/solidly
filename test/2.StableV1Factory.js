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

  it("mint & burn tokens for pair mim-usdt", async function () {
    const usdt_1 = ethers.BigNumber.from("1000000");
    const mim_1 = ethers.BigNumber.from("1000000000000000000");
    const lp = await pair.lp(mim_1/1e12, usdt_1/1);
    const before_balance = await usdt.balanceOf(owner.address);
    await usdt.transfer(pair.address, usdt_1);
    await mim.transfer(pair.address, mim_1);
    await pair.mint(owner.address);
    expect(await pair.balanceOf(owner.address)).to.equal(lp);

    await pair.transfer(pair.address, await pair.balanceOf(owner.address));
    await pair.burn(owner.address);
    expect(await usdt.balanceOf(owner.address)).to.equals(before_balance);
  });

  it("StableV1Router01 quoteAddLiquidity & addLiquidity", async function () {
    const usdt_1000 = ethers.BigNumber.from("1000000000");
    const mim_1000 = ethers.BigNumber.from("1000000000000000000000");
    const expected_2000 = ethers.BigNumber.from("2000000000");
    const min_liquidity = await router.quoteAddLiquidity(mim.address, usdt.address, mim_1000, usdt_1000);
    expect(min_liquidity).to.equal(expected_2000);
    await usdt.approve(router.address, ethers.BigNumber.from("1000000000000"));
    await mim.approve(router.address, ethers.BigNumber.from("1000000000000000000000000"));
    await router.addLiquidity(mim.address, usdt.address, mim_1000, usdt_1000, min_liquidity, owner.address, Date.now());
    expect(await pair.balanceOf(owner.address)).to.equal(min_liquidity);
  });

  it("StableV1Router01 getAmountsOut", async function () {
    const usdt_1 = ethers.BigNumber.from("1000000");
    const mim_1 = ethers.BigNumber.from("1000000000000000000");
    const expected_output = await router.getAmountsOut(usdt_1, [usdt.address, mim.address]);
    await router.swapExactTokensForTokens(usdt_1, expected_output[1], [usdt.address, mim.address], owner.address, Date.now());
    expect(await mim.balanceOf(owner.address)).to.equal(expected_output[1]);
  });


});
