# Metropolis in Ruins — V34

Jogo de estratégia econômica em Godot 4, com modo LAN por ENet e início da
migração do modo Online para Photon Fusion Godot.

## Configuração rápida do Photon

1. Crie uma conta no Photon Engine Dashboard.
2. Crie um aplicativo com **Photon SDK: Fusion** e **SDK Version: 3**.
3. Copie o App ID para `photon/photon_config.cfg`.
4. Baixe o Photon Fusion Godot SDK 3.
5. Copie a pasta `fusion` do SDK para `addons/fusion/`.
6. Reabra o projeto no Godot.
7. Abra **Online**, conecte-se e teste uma sala com o mesmo código em duas
   instâncias.

Instruções detalhadas: `photon/LEIA-ME_CONFIGURAR_PHOTON.txt`.

## Estado da integração

A V34 implementa conexão ao Photon Cloud e salas por código. O jogo ainda não
inicia a partida pelo Photon porque o lobby e o tabuleiro atuais dependem do
MultiplayerAPI/ENet. Essa migração será a próxima etapa.

O modo LAN existente continua disponível.
