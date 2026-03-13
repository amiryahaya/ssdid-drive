using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SsdidDrive.Api.Migrations
{
    /// <inheritdoc />
    public partial class ShamirRecovery : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "recovery_approvals");

            migrationBuilder.DropTable(
                name: "recovery_shares");

            migrationBuilder.DropTable(
                name: "recovery_requests");

            migrationBuilder.DropTable(
                name: "recovery_configs");

            migrationBuilder.AddColumn<bool>(
                name: "HasRecoverySetup",
                table: "users",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AlterColumn<string>(
                name: "ResourceType",
                table: "file_activities",
                type: "character varying(32)",
                maxLength: 32,
                nullable: false,
                oldClrType: typeof(string),
                oldType: "character varying(16)",
                oldMaxLength: 16);

            migrationBuilder.CreateTable(
                name: "recovery_setups",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    ServerShare = table.Column<string>(type: "text", nullable: false),
                    KeyProof = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    ShareCreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_recovery_setups", x => x.Id);
                    table.ForeignKey(
                        name: "FK_recovery_setups_users_UserId",
                        column: x => x.UserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_recovery_setups_UserId",
                table: "recovery_setups",
                column: "UserId",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "recovery_setups");

            migrationBuilder.DropColumn(
                name: "HasRecoverySetup",
                table: "users");

            migrationBuilder.AlterColumn<string>(
                name: "ResourceType",
                table: "file_activities",
                type: "character varying(16)",
                maxLength: 16,
                nullable: false,
                oldClrType: typeof(string),
                oldType: "character varying(32)",
                oldMaxLength: 32);

            migrationBuilder.CreateTable(
                name: "recovery_configs",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    Threshold = table.Column<int>(type: "integer", nullable: false),
                    TotalShares = table.Column<int>(type: "integer", nullable: false)
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
                    RecoveryConfigId = table.Column<Guid>(type: "uuid", nullable: false),
                    RequesterId = table.Column<Guid>(type: "uuid", nullable: false),
                    ApprovalsReceived = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    CompletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    Status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "pending")
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
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    EncryptedShare = table.Column<byte[]>(type: "bytea", nullable: false),
                    Status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "pending")
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

            migrationBuilder.CreateTable(
                name: "recovery_approvals",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    RecoveryRequestId = table.Column<Guid>(type: "uuid", nullable: false),
                    TrusteeId = table.Column<Guid>(type: "uuid", nullable: false),
                    ApprovedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    EncryptedShare = table.Column<byte[]>(type: "bytea", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_recovery_approvals", x => x.Id);
                    table.ForeignKey(
                        name: "FK_recovery_approvals_recovery_requests_RecoveryRequestId",
                        column: x => x.RecoveryRequestId,
                        principalTable: "recovery_requests",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_recovery_approvals_users_TrusteeId",
                        column: x => x.TrusteeId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_recovery_approvals_RecoveryRequestId_TrusteeId",
                table: "recovery_approvals",
                columns: new[] { "RecoveryRequestId", "TrusteeId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_recovery_approvals_TrusteeId",
                table: "recovery_approvals",
                column: "TrusteeId");

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
                name: "IX_recovery_shares_RecoveryConfigId_TrusteeId",
                table: "recovery_shares",
                columns: new[] { "RecoveryConfigId", "TrusteeId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_recovery_shares_TrusteeId",
                table: "recovery_shares",
                column: "TrusteeId");
        }
    }
}
