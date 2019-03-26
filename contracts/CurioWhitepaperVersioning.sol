pragma solidity ^0.5.3;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

/**
 * @title CurioWhitepaperVersioning
 * @dev Managing list of whitepapers associated with a contract address.
 * For ICO whitepaper version tracking purpose, the associated contract address shall be
 * usually token contract address or token sale contract address.
 * Contents of whitepapers is expected to be stored in IPFS.
 */
contract CurioWhitepaperVersioning {
    mapping (address => Whitepaper[]) private whitepapers;
    mapping (address => address) private authors;
    event Post(
      address indexed _contract,
      uint256 indexed _version,
      string _ipfsHash,
      address _author
    );

    struct Whitepaper {
        uint256 version;
        string ipfsHash;
    }

    /**
     * @dev Constructor.
     */
    constructor () public {}

    /**
     * @dev Function to post a new whitepaper.
     * @param _version uint256 Version number in integer
     * @param _ipfsHash string IPFS hash of the posting whitepaper
     * @return status bool
     */
    function pushWhitepaper (Ownable _contract, uint256 _version, string calldata _ipfsHash) external returns (bool) {
        uint256 num = whitepapers[address(_contract)].length;
        if(num == 0){
            // If the posting whitepaper is the initial, only the target contract owner can post.
            require(_contract.owner() == msg.sender);
            authors[address(_contract)] = msg.sender;
        }else{
            // Check if the initial version whitepaper's author is the msg.sender
            require(authors[address(_contract)] == msg.sender);
            // Check if the version is greater than the previous version
            require(whitepapers[address(_contract)][num-1].version < _version);
        }

        whitepapers[address(_contract)].push(Whitepaper(_version, _ipfsHash));
        emit Post(address(_contract), _version, _ipfsHash, msg.sender);
        return true;
    }

    /**
     * @dev Look up whitepaper at the specified index.
     * @param _contract address Target contract address associated with a whitepaper
     * @param _index uint256 Index number of whitepapers associated with the specified contract address
     * @return version uint8 Version number in integer
     * @return ipfsHash string IPFS hash of the whitepaper
     * @return author address Address of an account who posted the whitepaper
     */
    function getWhitepaperAt (address _contract, uint256 _index) public view returns (
        uint256 version,
        string memory ipfsHash,
        address author
    ) {
        return (
            whitepapers[_contract][_index].version,
            whitepapers[_contract][_index].ipfsHash,
            authors[_contract]
        );
    }

    /**
     * @dev Look up whitepaper at the specified index.
     * @param _contract address Target contract address associated with a whitepaper
     * @return version uint8 Version number in integer
     * @return ipfsHash string IPFS hash of the whitepaper
     * @return author address Address of an account who posted the whitepaper
     */
    function getLatestWhitepaper (address _contract) external view returns (
        uint256 version,
        string memory ipfsHash,
        address author
    ) {
        uint256 latest = whitepapers[_contract].length - 1;
        return getWhitepaperAt(_contract, latest);
    }
}

