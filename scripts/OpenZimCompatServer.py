"""Passerelle MCP simplifiee pour les petits modeles locaux.

GPT-OSS 20B peut produire des appels JSON invalides lorsqu'un outil expose de
nombreux parametres facultatifs. Cette passerelle publie trois outils aux
schemas courts, puis delegue leur execution a l'outil ``zim_query`` officiel
d'OpenZIM MCP. Elle ne modifie pas le paquet OpenZIM installe.
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path
from typing import Any

from mcp.server.mcpserver import MCPServer
from openzim_mcp.config import OpenZimMcpConfig
from openzim_mcp.server import OpenZimMcpServer


def parse_arguments() -> argparse.Namespace:
    """Lire et valider les dossiers ZIM fournis par la configuration MCP."""

    parser = argparse.ArgumentParser(
        description="Passerelle MCP OpenZIM simplifiee pour les modeles locaux."
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Verifier le chargement d'OpenZIM et des archives, puis quitter.",
    )
    parser.add_argument(
        "directories",
        nargs="+",
        help="Dossiers autorises contenant les archives ZIM.",
    )
    arguments = parser.parse_args()

    missing = [path for path in arguments.directories if not Path(path).is_dir()]
    if missing:
        parser.error("Dossier ZIM introuvable : " + ", ".join(missing))
    return arguments


def render_tool_result(result: Any) -> str:
    """Convertir une reponse MCP OpenZIM en texte sans perdre ses erreurs."""

    text_blocks = [
        block.text
        for block in getattr(result, "content", [])
        if isinstance(getattr(block, "text", None), str)
    ]
    if text_blocks:
        return "\n".join(text_blocks)
    return str(result)


class OpenZimBridge:
    """Adapter l'API riche d'OpenZIM a des appels faciles a generer."""

    def __init__(self, directories: list[str]) -> None:
        config = OpenZimMcpConfig(
            allowed_directories=directories,
            tool_mode="simple",
            transport="stdio",
        )
        self.backend = OpenZimMcpServer(config)

    async def query(self, query: str, zim_file_path: str | None = None) -> str:
        """Appeler le vrai outil zim_query avec uniquement des valeurs valides."""

        clean_query = query.strip()
        if not clean_query:
            raise ValueError("La question OpenZIM ne peut pas etre vide.")

        arguments: dict[str, Any] = {"query": clean_query}
        if zim_file_path is not None:
            clean_path = zim_file_path.strip()
            if not clean_path:
                raise ValueError("Le chemin de l'archive ZIM ne peut pas etre vide.")
            arguments["zim_file_path"] = clean_path

        result = await self.backend.mcp.call_tool("zim_query", arguments)
        return render_tool_result(result)

    def close(self) -> None:
        """Fermer proprement le cache du serveur delegue."""

        self.backend.cache.shutdown()


def build_server(bridge: OpenZimBridge) -> MCPServer:
    """Creer la surface MCP minimale presentee aux modeles locaux."""

    server = MCPServer(
        "openzim-compatible",
        title="OpenZIM MCP - compatibilite modeles locaux",
        description="Recherche hors ligne dans les archives ZIM locales.",
        instructions=(
            "Commencez par openzim_list_archives. Utilisez ensuite "
            "openzim_search ou openzim_search_archive. N'inventez jamais "
            "un chemin d'archive."
        ),
    )

    @server.tool(description="Lister les archives ZIM locales disponibles.")
    async def openzim_list_archives() -> str:
        return await bridge.query("list available ZIM files")

    @server.tool(description="Rechercher une question dans toute la base ZIM locale.")
    async def openzim_search(query: str) -> str:
        # Sans archive explicite, zim_query peut refuser une question libre des
        # qu'il existe plusieurs ZIM. Cette intention est documentee par son
        # message de recuperation et garantit la recherche multi-archives.
        clean_query = query.strip()
        if not clean_query:
            raise ValueError("La question OpenZIM ne peut pas etre vide.")
        return await bridge.query("search all files for " + clean_query)

    @server.tool(description="Rechercher dans une archive ZIM deja listee.")
    async def openzim_search_archive(query: str, zim_file_path: str) -> str:
        return await bridge.query(query, zim_file_path)

    return server


async def run_self_test(bridge: OpenZimBridge, server: MCPServer) -> int:
    """Verifier les schemas simples et l'acces effectif a la bibliotheque."""

    tools = await server.list_tools()
    expected_names = {
        "openzim_list_archives",
        "openzim_search",
        "openzim_search_archive",
    }
    actual_names = {tool.name for tool in tools}
    if actual_names != expected_names:
        print(
            "ECHEC : outils MCP inattendus : " + ", ".join(sorted(actual_names)),
            file=sys.stderr,
        )
        return 1

    expected_properties = {
        "openzim_list_archives": set(),
        "openzim_search": {"query"},
        "openzim_search_archive": {"query", "zim_file_path"},
    }
    for tool in tools:
        schema = tool.input_schema
        properties = set(schema.get("properties", {}))
        required = set(schema.get("required", []))
        if properties != expected_properties[tool.name] or required != properties:
            print(
                f"ECHEC : schema MCP complexe ou facultatif pour {tool.name}.",
                file=sys.stderr,
            )
            return 1

    listing = await bridge.query("list available ZIM files")
    if "ZIM file" not in listing and '"path"' not in listing:
        print("ECHEC : OpenZIM n'a retourne aucune archive lisible.", file=sys.stderr)
        return 1

    print("OK : passerelle MCP chargee, 3 outils simples et archives ZIM accessibles.")
    return 0


def main() -> int:
    """Executer l'auto-test ou servir le protocole MCP sur l'entree standard."""

    arguments = parse_arguments()
    bridge = OpenZimBridge(arguments.directories)
    server = build_server(bridge)
    try:
        if arguments.self_test:
            return asyncio.run(run_self_test(bridge, server))
        server.run(transport="stdio")
        return 0
    finally:
        bridge.close()


if __name__ == "__main__":
    raise SystemExit(main())
