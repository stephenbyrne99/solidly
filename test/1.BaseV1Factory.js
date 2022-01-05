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

describe("BaseV1Factory", function () {

  let token;
  let ust;
  let mim;
  let ve;
  let factory;
  let router;
  let pair;
  let owner;
  let gauge_factory;
  let gauge;
  let bribe;

  it("deploy base coins", async function () {
    [owner] = await ethers.getSigners();
    token = await ethers.getContractFactory("Token");
    ust = await token.deploy('ust', 'ust', 6, owner.address);
    await ust.mint(owner.address, ethers.BigNumber.from("1000000000000000"));
    mim = await token.deploy('MIM', 'MIM', 18, owner.address);
    await mim.mint(owner.address, ethers.BigNumber.from("1000000000000000000000"));
    ve = await token.deploy('VE', 'VE', 18, owner.address);
    await ve.mint(owner.address, ethers.BigNumber.from("10000000000000000000000000000"));

    ust.deployed();
    mim.deployed();
  });

  it("confirm ust deployment", async function () {
    expect(await ust.name()).to.equal("ust");
  });

  it("confirm mim deployment", async function () {
    expect(await mim.name()).to.equal("MIM");
  });

  it("deploy BaseV1Factory and test pair length", async function () {
    const BaseV1Factory = await ethers.getContractFactory("BaseV1Factory");
    factory = await BaseV1Factory.deploy();
    await factory.deployed();
    console.log(await factory.pairCodeHash());

    expect(await factory.allPairsLength()).to.equal(0);
  });

  it("deploy BaseV1Router and test factory address", async function () {
    const BaseV1Router = await ethers.getContractFactory("BaseV1Router01");
    router = await BaseV1Router.deploy(factory.address);
    await router.deployed();

    expect(await router.factory()).to.equal(factory.address);
  });

  it("deploy pair via BaseV1Factory", async function () {
    await factory.createPair(mim.address, ust.address, true);
    expect(await factory.allPairsLength()).to.equal(1);
  });

  it("confirm pair for mim-ust", async function () {
    const create2address = await router.pairFor(mim.address, ust.address);
    const BaseV1Pair = await ethers.getContractFactory("BaseV1Pair");
    const address = await factory.getPair(mim.address, ust.address);
    const allpairs0 = await factory.allPairs(0);
    pair = await BaseV1Pair.attach(address);

    expect(pair.address).to.equal(create2address);
  });

  it("confirm tokens for mim-ust", async function () {
    [token0, token1] = await router.sortTokens(ust.address, mim.address);
    expect((await pair.token0()).toUpperCase()).to.equal(token0.toUpperCase());
    expect((await pair.token1()).toUpperCase()).to.equal(token1.toUpperCase());
  });

  it("mint & burn tokens for pair mim-ust", async function () {
    const ust_1 = ethers.BigNumber.from("1000000");
    const mim_1 = ethers.BigNumber.from("1000000000000000000");
    const before_balance = await ust.balanceOf(owner.address);
    await ust.transfer(pair.address, ust_1);
    await mim.transfer(pair.address, mim_1);
    await pair.mint(owner.address);

    await pair.transfer(pair.address, await pair.balanceOf(owner.address));
    await pair.burn(owner.address);
    expect(await ust.balanceOf(owner.address)).to.equals(before_balance-1);
  });

  it("BaseV1Router01 quoteAddLiquidity & addLiquidity", async function () {
    const ust_1000 = ethers.BigNumber.from("1000000000");
    const mim_1000 = ethers.BigNumber.from("1000000000000000000000");
    const expected_2000 = ethers.BigNumber.from("2000000000");
    await ust.approve(router.address, ethers.BigNumber.from("1000000000000"));
    await mim.approve(router.address, ethers.BigNumber.from("1000000000000000000000000"));
    await router.addLiquidity(mim.address, ust.address, mim_1000, ust_1000, min_liquidity, owner.address, Date.now());
    expect(await pair.balanceOf(owner.address)).to.equal(min_liquidity);
  });

  it("BaseV1Router01 getAmountsOut & swapExactTokensForTokens", async function () {
    const ust_1 = ethers.BigNumber.from("1000000");
    const mim_1 = ethers.BigNumber.from("1000000000000000000");
    const expected_output = await router.getAmountsOut(ust_1, [ust.address, mim.address]);
    await router.swapExactTokensForTokens(ust_1, expected_output[1], [ust.address, mim.address], owner.address, Date.now());
    expect(await mim.balanceOf(owner.address)).to.equal(expected_output[1]);
  });

  it("deploy BaseV1Factory and test pair length", async function () {
    const BaseV1Gauges = await ethers.getContractFactory("BaseV1Gauges");
    gauge_factory = await BaseV1Gauges.deploy(ve.address, factory.address);
    await gauge_factory.deployed();

    expect(await gauge_factory.length()).to.equal(0);
  });

  it("deploy BaseV1Factory gauge", async function () {
    const pair_1000 = ethers.BigNumber.from("1000000000");

    await gauge_factory.createGauge(pair.address);
    expect(await gauge_factory.gauges(pair.address)).to.not.equal(0x0000000000000000000000000000000000000000);

    const gauge_address = await gauge_factory.gauges(pair.address);
    const bribe_address = await gauge_factory.bribes(gauge_address);

    const Gauge = await ethers.getContractFactory("Gauge");
    gauge = await Gauge.attach(gauge_address);

    const Bribe = await ethers.getContractFactory("Bribe");
    bribe = await Bribe.attach(bribe_address);

    await pair.approve(gauge.address, pair_1000);
    await gauge.deposit(pair_1000, owner.address);
    expect(await gauge.totalSupply()).to.equal(pair_1000);
    expect(await gauge.earned(ve.address, owner.address)).to.equal(0);
  });

  it("withdraw gauge stake", async function () {
    await gauge.exit();
    expect(await gauge.totalSupply()).to.equal(0);
  });

  it("add gauge & bribe rewards", async function () {
    const pair_1000 = ethers.BigNumber.from("1000000000");

    await ve.approve(gauge.address, pair_1000);
    await ve.approve(bribe.address, pair_1000);

    await gauge.notifyRewardAmount(ve.address, pair_1000);
    await bribe.notifyRewardAmount(ve.address, pair_1000);

    expect(await gauge.rewardRate(ve.address)).to.equal(ethers.BigNumber.from(1653));
    expect(await bribe.rewardRate(ve.address)).to.equal(ethers.BigNumber.from(1653));
  });

  it("exit & getReward gauge stake", async function () {
    const pair_1000 = ethers.BigNumber.from("1000000000");
    await pair.approve(gauge.address, pair_1000);
    await gauge.deposit(pair_1000, owner.address);
    await gauge.exit();
    expect(await gauge.totalSupply()).to.equal(0);
  });

  it("gauge reset", async function () {
    await gauge_factory.reset();
  });

  it("gauge poke self", async function () {
    await gauge_factory.poke(owner.address);
  });

  it("gauge vote & bribe balanceOf", async function () {
    await gauge_factory.vote([pair.address], [100]);
    expect(await gauge_factory.totalWeight()).to.not.equal(0);
    expect(await bribe.balanceOf(owner.address)).to.not.equal(0);
  });

  it("gauge distribute based on voting", async function () {
    const pair_1000 = ethers.BigNumber.from("1000000000");
    await gauge_factory.distribute();
    await ve.transfer(gauge_factory.address, pair_1000);
    await gauge_factory.distribute();
  });

  it("bribe claim rewards", async function () {
    await bribe.getReward(ve.address);
  });

});
