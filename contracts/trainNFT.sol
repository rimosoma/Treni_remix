// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Importazione delle librerie di OpenZeppelin necessarie
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol"; // Per la conversione degli ID in stringa
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title TrainNFT - Contratto per la gestione di treni e vagoni come NFT
/// @notice Il contratto crea un NFT per ogni treno; ogni treno ha vagoni con ID univoci e documenti associati tramite IPFS.
/// @dev I file TXT con i dati devono essere generati off-chain e caricati su IPFS (es. tramite Pinata o Infura IPFS API).
contract TrainNFT is ERC721, AccessControl {
    using Counters for Counters.Counter;  // Libreria per generare ID univoci
    using Strings for uint256;            // Libreria per convertire uint256 in stringa

    Counters.Counter private _tokenIds;   // Contatore per gli ID dei treni
    Counters.Counter private _wagonIds;     // Contatore per gli ID dei vagoni

    // Ruolo per i manutentori, che possono aggiornare stato e documenti
    bytes32 public constant MAINTAINER_ROLE = keccak256("MAINTAINER_ROLE");

    /// @notice Struttura che rappresenta un vagone
    struct Wagon {
        uint256 wagonUniqueId; // ID univoco assegnato automaticamente al vagone
        string wagonCode;      // Codice del vagone generato automaticamente (es. "WAG-1")
        string status;         // Stato operativo del vagone (es. "Operativo", "InManutenzione")
        string documentHash;   // IPFS hash del documento TXT associato al vagone (inizialmente vuoto)
    }

    /// @notice Struttura che rappresenta un treno
    struct TrainData {
        uint256 trainId;       // ID univoco del treno
        Wagon[] wagons;        // Array dei vagoni che compongono il treno
        string status;         // Stato operativo del treno
        string documentHash;   // IPFS hash del documento TXT associato al treno (inizialmente vuoto)
    }

    // Mappatura che associa un ID del treno ai relativi dati
    mapping(uint256 => TrainData) public trainData;

    // Eventi per tracciare le operazioni
    event TrainMinted(uint256 indexed trainId, address indexed owner);
    event TrainDocumentLinked(uint256 indexed trainId, string documentHash);
    event StatusUpdated(uint256 indexed trainId, string newStatus);
    event WagonStatusUpdated(uint256 indexed trainId, uint256 wagonUniqueId, string newStatus);
    event DocumentLinkedToWagon(uint256 indexed trainId, uint256 wagonUniqueId, string documentHash);

    /// @notice Costruttore del contratto
    /// @param admin Indirizzo a cui verrà assegnato il ruolo di amministratore
    constructor(address admin) ERC721("TrainNFT", "TRAIN") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Override della funzione supportsInterface per gestire l'ereditarietà multipla
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Crea un nuovo treno NFT con un numero specificato di vagoni
    /// @param owner Indirizzo del proprietario del treno
    /// @param numWagons Numero di vagoni iniziali per il treno
    /// @return newTrainId L'ID del treno appena creato
    /// @dev I documenti TXT verranno generati off-chain e associati successivamente
    function mintTrain(address owner, uint256 numWagons) public onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
        _tokenIds.increment();                   // Incrementa il contatore dei treni
        uint256 newTrainId = _tokenIds.current();  // Ottiene il nuovo ID del treno

        _mint(owner, newTrainId);                  // Assegna il nuovo NFT del treno al proprietario

        // Inizializza i dati del treno
        TrainData storage newTrain = trainData[newTrainId];
        newTrain.trainId = newTrainId;
        newTrain.status = "Operativo";             // Stato di default
        newTrain.documentHash = "";                // Documento ancora non associato

        // Crea automaticamente i vagoni in base al numero specificato
        for (uint256 i = 0; i < numWagons; i++) {
            _wagonIds.increment();                            // Incrementa il contatore dei vagoni
            uint256 newWagonId = _wagonIds.current();           // Ottiene il nuovo ID del vagone
            // Genera un codice univoco per il vagone, es. "WAG-<id>"
            string memory wagonCode = string(abi.encodePacked("WAG-", newWagonId.toString()));
            // Crea il nuovo vagone con stato "Operativo" e documento vuoto
            Wagon memory newWagon = Wagon({
                wagonUniqueId: newWagonId,
                wagonCode: wagonCode,
                status: "Operativo",
                documentHash: ""
            });
            newTrain.wagons.push(newWagon); // Aggiunge il vagone al treno
        }

        emit TrainMinted(newTrainId, owner); // Emissione dell'evento di creazione del treno
        return newTrainId;                   // Restituisce l'ID del treno creato
    }

    /// @notice Aggiorna lo stato operativo di un treno
    /// @param trainId ID del treno
    /// @param newStatus Nuovo stato del treno (es. "InManutenzione")
    function updateTrainStatus(uint256 trainId, string memory newStatus) public onlyRole(MAINTAINER_ROLE) {
        require(ownerOf(trainId) != address(0), "Train does not exist");
        trainData[trainId].status = newStatus;
        emit StatusUpdated(trainId, newStatus);
    }

    /// @notice Aggiorna lo stato operativo di un vagone specifico
    /// @param trainId ID del treno a cui appartiene il vagone
    /// @param wagonUniqueId ID univoco del vagone
    /// @param newStatus Nuovo stato del vagone (es. "InManutenzione")
    function updateWagonStatus(uint256 trainId, uint256 wagonUniqueId, string memory newStatus) public onlyRole(MAINTAINER_ROLE) {
        require(ownerOf(trainId) != address(0), "Train does not exist");
        Wagon[] storage wagons = trainData[trainId].wagons;
        for (uint256 i = 0; i < wagons.length; i++) {
            if (wagons[i].wagonUniqueId == wagonUniqueId) {
                wagons[i].status = newStatus;
                emit WagonStatusUpdated(trainId, wagonUniqueId, newStatus);
                return;
            }
        }
        revert("Wagon not found");
    }

    /// @notice Associa (o aggiorna) il documento TXT di un vagone tramite l'hash IPFS
    /// @param trainId ID del treno a cui appartiene il vagone
    /// @param wagonUniqueId ID univoco del vagone
    /// @param ipfsHash IPFS hash del documento TXT (generato off-chain tramite Pinata, Infura IPFS, ecc.)
    function linkWagonDocument(uint256 trainId, uint256 wagonUniqueId, string memory ipfsHash) public onlyRole(MAINTAINER_ROLE) {
        require(ownerOf(trainId) != address(0), "Train does not exist");
        Wagon[] storage wagons = trainData[trainId].wagons;
        for (uint256 i = 0; i < wagons.length; i++) {
            if (wagons[i].wagonUniqueId == wagonUniqueId) {
                wagons[i].documentHash = ipfsHash;
                emit DocumentLinkedToWagon(trainId, wagonUniqueId, ipfsHash);
                return;
            }
        }
        revert("Wagon not found");
    }

    /// @notice Associa (o aggiorna) il documento TXT di un treno tramite l'hash IPFS
    /// @param trainId ID del treno
    /// @param ipfsHash IPFS hash del documento TXT associato al treno
    function linkTrainDocument(uint256 trainId, string memory ipfsHash) public onlyRole(MAINTAINER_ROLE) {
        require(ownerOf(trainId) != address(0), "Train does not exist");
        trainData[trainId].documentHash = ipfsHash;
        emit TrainDocumentLinked(trainId, ipfsHash);
    }

    /// @notice Ottiene tutti gli hash dei documenti associati ai vagoni di un treno
    /// @param trainId ID del treno
    /// @return allDocuments Array di IPFS hash dei documenti dei vagoni
    function getAllWagonDocuments(uint256 trainId) public view returns (string[] memory) {
        require(ownerOf(trainId) != address(0), "Train does not exist");
        Wagon[] storage wagons = trainData[trainId].wagons;
        uint256 totalWagons = wagons.length;
        string[] memory allDocuments = new string[](totalWagons);
        for (uint256 i = 0; i < totalWagons; i++) {
            allDocuments[i] = wagons[i].documentHash;
        }
        return allDocuments;
    }
}
