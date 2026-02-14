"""Custom exceptions for mcp_agent_mail."""

from __future__ import annotations

from typing import Optional


class ToolExecutionError(Exception):
    """Exception raised when a tool execution fails with recoverable or non-recoverable errors."""

    def __init__(
        self,
        error_type: str,
        message: str,
        *,
        recoverable: bool = True,
        data: Optional[dict[str, object]] = None,
    ):
        """Initialize ToolExecutionError.

        Parameters
        ----------
        error_type : str
            The type of error (e.g., "NOT_FOUND", "INVALID_ARGUMENT").
        message : str
            Human-readable error message.
        recoverable : bool, optional
            Whether the error is recoverable, by default True.
        data : dict, optional
            Additional error context data, by default None.
        """
        super().__init__(message)
        self.error_type = error_type
        self.recoverable = recoverable
        self.data = data or {}

    def to_payload(self) -> dict[str, object]:
        """Convert error to MCP-compatible payload format.

        Returns
        -------
        dict
            Error payload with type, message, recoverable flag, and data.
        """
        return {
            "error": {
                "type": self.error_type,
                "message": str(self),
                "recoverable": self.recoverable,
                "data": self.data,
            }
        }
