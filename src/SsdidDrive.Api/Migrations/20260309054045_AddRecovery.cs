using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SsdidDrive.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddRecovery : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "recovery_configs",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Threshold = table.Column<int>(type: "integer", nullable: false),
                    TotalShares = table.Column<int>(type: "integer", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_recovery_configs", x => x.Id);
                    table.ForeignKey(
                        name: "FK_recovery_configs_users_UserId",
                        column: x => x.UserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "recovery_requests",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    RequesterId = table.Column<Guid>(type: "uuid", nullable: false),
                    RecoveryConfigId = table.Column<Guid>(type: "uuid", nullable: false),
                    Status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "pending"),
                    ApprovalsReceived = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_recovery_requests", x => x.Id);
                    table.ForeignKey(
                        name: "FK_recovery_requests_recovery_configs_RecoveryConfigId",
                        column: x => x.RecoveryConfigId,
                        principalTable: "recovery_configs",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_recovery_requests_users_RequesterId",
                        column: x => x.RequesterId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "recovery_shares",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    RecoveryConfigId = table.Column<Guid>(type: "uuid", nullable: false),
                    TrusteeId = table.Column<Guid>(type: "uuid", nullable: false),
                    EncryptedShare = table.Column<byte[]>(type: "bytea", nullable: false),
                    Status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "pending"),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_recovery_shares", x => x.Id);
                    table.ForeignKey(
                        name: "FK_recovery_shares_recovery_configs_RecoveryConfigId",
                        column: x => x.RecoveryConfigId,
                        principalTable: "recovery_configs",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_recovery_shares_users_TrusteeId",
                        column: x => x.TrusteeId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_recovery_configs_UserId",
                table: "recovery_configs",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_recovery_requests_RecoveryConfigId",
                table: "recovery_requests",
                column: "RecoveryConfigId");

            migrationBuilder.CreateIndex(
                name: "IX_recovery_requests_RequesterId",
                table: "recovery_requests",
                column: "RequesterId");

            migrationBuilder.CreateIndex(
                name: "IX_recovery_shares_RecoveryConfigId",
                table: "recovery_shares",
                column: "RecoveryConfigId");

            migrationBuilder.CreateIndex(
                name: "IX_recovery_shares_TrusteeId",
                table: "recovery_shares",
                column: "TrusteeId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "recovery_requests");

            migrationBuilder.DropTable(
                name: "recovery_shares");

            migrationBuilder.DropTable(
                name: "recovery_configs");
        }
    }
}
