using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SsdidDrive.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddTrusteeRecovery : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_notification_logs_users_SentById",
                table: "notification_logs");

            migrationBuilder.AddColumn<int>(
                name: "Threshold",
                table: "recovery_setups",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AlterColumn<Guid>(
                name: "SentById",
                table: "notification_logs",
                type: "uuid",
                nullable: true,
                oldClrType: typeof(Guid),
                oldType: "uuid");

            migrationBuilder.CreateTable(
                name: "recovery_requests",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    RequesterId = table.Column<Guid>(type: "uuid", nullable: false),
                    RecoverySetupId = table.Column<Guid>(type: "uuid", nullable: false),
                    Status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "pending"),
                    ApprovedCount = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    RequiredCount = table.Column<int>(type: "integer", nullable: false),
                    ExpiresAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_recovery_requests", x => x.Id);
                    table.ForeignKey(
                        name: "FK_recovery_requests_recovery_setups_RecoverySetupId",
                        column: x => x.RecoverySetupId,
                        principalTable: "recovery_setups",
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
                name: "recovery_trustees",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    RecoverySetupId = table.Column<Guid>(type: "uuid", nullable: false),
                    TrusteeUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    EncryptedShare = table.Column<byte[]>(type: "bytea", nullable: false),
                    ShareIndex = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_recovery_trustees", x => x.Id);
                    table.ForeignKey(
                        name: "FK_recovery_trustees_recovery_setups_RecoverySetupId",
                        column: x => x.RecoverySetupId,
                        principalTable: "recovery_setups",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_recovery_trustees_users_TrusteeUserId",
                        column: x => x.TrusteeUserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "recovery_request_approvals",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    RecoveryRequestId = table.Column<Guid>(type: "uuid", nullable: false),
                    TrusteeUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Decision = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    DecidedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_recovery_request_approvals", x => x.Id);
                    table.ForeignKey(
                        name: "FK_recovery_request_approvals_recovery_requests_RecoveryReques~",
                        column: x => x.RecoveryRequestId,
                        principalTable: "recovery_requests",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_recovery_request_approvals_users_TrusteeUserId",
                        column: x => x.TrusteeUserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_recovery_request_approvals_RecoveryRequestId_TrusteeUserId",
                table: "recovery_request_approvals",
                columns: new[] { "RecoveryRequestId", "TrusteeUserId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_recovery_request_approvals_TrusteeUserId",
                table: "recovery_request_approvals",
                column: "TrusteeUserId");

            migrationBuilder.CreateIndex(
                name: "IX_recovery_requests_RecoverySetupId",
                table: "recovery_requests",
                column: "RecoverySetupId");

            migrationBuilder.CreateIndex(
                name: "IX_recovery_requests_RequesterId",
                table: "recovery_requests",
                column: "RequesterId");

            migrationBuilder.CreateIndex(
                name: "IX_recovery_requests_RequesterId_Status",
                table: "recovery_requests",
                columns: new[] { "RequesterId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_recovery_trustees_RecoverySetupId",
                table: "recovery_trustees",
                column: "RecoverySetupId");

            migrationBuilder.CreateIndex(
                name: "IX_recovery_trustees_RecoverySetupId_TrusteeUserId",
                table: "recovery_trustees",
                columns: new[] { "RecoverySetupId", "TrusteeUserId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_recovery_trustees_TrusteeUserId",
                table: "recovery_trustees",
                column: "TrusteeUserId");

            migrationBuilder.AddForeignKey(
                name: "FK_notification_logs_users_SentById",
                table: "notification_logs",
                column: "SentById",
                principalTable: "users",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_notification_logs_users_SentById",
                table: "notification_logs");

            migrationBuilder.DropTable(
                name: "recovery_request_approvals");

            migrationBuilder.DropTable(
                name: "recovery_trustees");

            migrationBuilder.DropTable(
                name: "recovery_requests");

            migrationBuilder.DropColumn(
                name: "Threshold",
                table: "recovery_setups");

            migrationBuilder.AlterColumn<Guid>(
                name: "SentById",
                table: "notification_logs",
                type: "uuid",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"),
                oldClrType: typeof(Guid),
                oldType: "uuid",
                oldNullable: true);

            migrationBuilder.AddForeignKey(
                name: "FK_notification_logs_users_SentById",
                table: "notification_logs",
                column: "SentById",
                principalTable: "users",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);
        }
    }
}
