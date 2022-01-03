const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("StableV1Factory", function () {
  it("deploy and test pair length", async function () {
    const StableV1Factory = await ethers.getContractFactory("StableV1Factory");
    const factory = await StableV1Factory.deploy();
    await factory.deployed();

    expect(await factory.allPairsLength()).to.equal(0);
  });
});
